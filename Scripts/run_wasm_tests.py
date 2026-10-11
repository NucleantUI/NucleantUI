#!/usr/bin/env python3
"""Build NucleantUI's tests for WebAssembly and run them in headless Chrome.

In the browser a window is a <canvas>, its frame loop is the page's
requestAnimationFrame, and the engine is Vulkan on the page's WebGPU — so
the tests run in a page: NucleantApplication's test page (Web/test), which
gives the module the same three hosts an app gets (WASI, the WebGPU bridge,
the DOM bridge). The library's resource bundles are mounted at
NUCLEANT_APP_PATH as they are for an app, so the bundled fonts load. Any
WebGPU validation error fails the run.

    python3 Scripts/run_wasm_tests.py [--chrome PATH] [-- <test arguments>]

    python3 Scripts/run_wasm_tests.py -- --filter BrowserTests

Needs the wasm Swift SDK with its matching toolchain, the sibling
NucleantApplication and NucleantVulkan checkouts (their Web/ directories),
and NucleantVulkan's Web/naga_webgpu.wasm (its scripts/build_naga_wasm.py).
Chrome: --chrome, else $CHROME, else the usual install locations (any Chrome
with WebGPU and JSPI, i.e. 137+).
"""

from __future__ import annotations

import argparse
import functools
import http.server
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import urllib.parse
from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve().parent.parent
SCRATCH = PACKAGE_ROOT / ".build" / "wasm"
VERSION_RE = re.compile(r"(\d+\.\d+(?:\.\d+)?)")
PRODUCT = "NucleantUIPackageTests"
# NucleantVulkan's page files, which the test page finds next to nucleant-app.js.
NUCLEANT_VULKAN_WEB = {"nucleant-webgpu.js", "nucleant-wgpu.js", "nucleant-wasi.js", "naga_webgpu.wasm"}
# The driver's default wasm stack is 128 KB, placed after the data and growing
# into it: building view trees in a debug build overruns it and corrupts
# memory silently. 8 MB, as for an app (NucleantApplication's
# build_wasm_app.py). A toolset, because -Xlinker would also reach the host
# link of the `@View` macro plugin.
TOOLSET = {
    "schemaVersion": "1.0",
    "linker": {"extraCLIOptions": ["-z", f"stack-size={8 * 1024 * 1024}"]},
}

CHROME_CANDIDATES = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
]


def find_wasm_sdk() -> tuple[str, str]:
    """(swift executable, SDK id) for the newest installed *_wasm SDK whose toolchain exists."""
    roots = [Path.home() / "Library" / "org.swift.swiftpm" / "swift-sdks", Path.home() / ".swiftpm" / "swift-sdks"]
    for root in roots:
        for bundle in sorted(root.glob("*_wasm.artifactbundle"), reverse=True):
            sdk = bundle.name.removesuffix(".artifactbundle")
            version = VERSION_RE.search(sdk).group(1)
            for base in (Path.home() / "Library" / "Developer" / "Toolchains", Path("/Library/Developer/Toolchains")):
                swift = base / f"swift-{version}-RELEASE.xctoolchain" / "usr" / "bin" / "swift"
                if swift.is_file():
                    return str(swift), sdk
    sys.exit("error: no wasm Swift SDK with a matching toolchain found")


def find_chrome(explicit: str | None) -> str:
    for candidate in [explicit, os.environ.get("CHROME"), *CHROME_CANDIDATES]:
        if candidate and Path(candidate).is_file():
            return candidate
    sys.exit("error: no Chrome found; pass --chrome PATH or set CHROME")


def sibling_web(name: str, marker: str) -> Path:
    """`name`'s Web/ — the sibling checkout in a development tree, else SwiftPM's."""
    for candidate in (PACKAGE_ROOT.parent / name / "Web", SCRATCH / "checkouts" / name / "Web"):
        if (candidate / marker).is_file():
            return candidate
    sys.exit(f"error: {name}'s Web/ directory not found")


def build_tests() -> Path:
    swift, sdk = find_wasm_sdk()
    SCRATCH.mkdir(parents=True, exist_ok=True)
    toolset = SCRATCH / "test-toolset.json"
    toolset.write_text(json.dumps(TOOLSET, indent=2))
    command = [swift, "build", "--swift-sdk", sdk, "--toolset", str(toolset), "--scratch-path", str(SCRATCH),
               "--product", PRODUCT]
    print("+", " ".join(command), flush=True)
    env = dict(os.environ, WASM_BUILD="1")
    if subprocess.run(command, cwd=PACKAGE_ROOT, env=env).returncode != 0:
        sys.exit("error: building the tests for wasm failed")
    product = SCRATCH / "debug" / f"{PRODUCT}.xctest"
    if not product.is_file():
        sys.exit(f"error: expected {product}")
    return product


def resources_manifest(products: Path) -> dict:
    """The resource bundles next to the test product, as resources.json lists them."""
    files = sorted(
        path.relative_to(products).as_posix()
        for bundle in products.glob("*.resources") if bundle.is_dir()
        for path in bundle.rglob("*") if path.is_file()
    )
    # buildRoot: mounted there too, where `Bundle.module` looks (build_wasm_app.py).
    return {"root": "/app", "buildRoot": str(products.resolve()),
            "base": "/" + products.relative_to(PACKAGE_ROOT).as_posix() + "/", "files": files}


class Handler(http.server.SimpleHTTPRequestHandler):
    """Serves the package, the page under /Web/, resources.json, and the page's reports."""

    app_web: Path
    vulkan_web: Path
    manifest: bytes
    done = threading.Event()
    status = 1

    def translate_path(self, path):
        name = urllib.parse.urlparse(path).path
        if name.startswith("/Web/"):
            rest = name[len("/Web/"):]
            return str((self.vulkan_web if rest in NUCLEANT_VULKAN_WEB else self.app_web) / rest)
        return super().translate_path(path)

    def do_GET(self):
        if urllib.parse.urlparse(self.path).path == "/resources.json":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(self.manifest)))
            self.end_headers()
            self.wfile.write(self.manifest)
            return
        super().do_GET()

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode("utf-8", "replace")
        if self.path == "/log":
            print(body, flush=True)
        elif self.path == "/done":
            Handler.status = int(body or 1)
            Handler.done.set()
        self.send_response(204)
        self.end_headers()

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, *args):
        pass


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--chrome", help="Chrome executable")
    parser.add_argument("--timeout", type=float, default=600, help="seconds before giving up")
    parser.add_argument("--headed", action="store_true", help="show the browser window")
    parser.add_argument("test_args", nargs="*", help="arguments for the test runner (after --)")
    args = parser.parse_args(argv)

    chrome = find_chrome(args.chrome)
    Handler.app_web = sibling_web("NucleantApplication", "test/runner.js")
    Handler.vulkan_web = sibling_web("NucleantVulkan", "nucleant-webgpu.js")
    if not (Handler.vulkan_web / "naga_webgpu.wasm").is_file():
        sys.exit("error: NucleantVulkan's Web/naga_webgpu.wasm is missing; run its scripts/build_naga_wasm.py")
    product = build_tests()
    Handler.manifest = json.dumps(resources_manifest(product.parent)).encode()

    handler = functools.partial(Handler, directory=str(PACKAGE_ROOT))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    query = urllib.parse.urlencode({
        "wasm": "/" + product.relative_to(PACKAGE_ROOT).as_posix(),
        # The tests are Swift Testing; SwiftPM's runner defaults to XCTest.
        "args": json.dumps(["--testing-library", "swift-testing", *args.test_args]),
        "resources": "/resources.json",
        "name": PRODUCT,
    })
    url = f"http://127.0.0.1:{server.server_address[1]}/Web/test/index.html?{query}"
    print(f"[run_wasm_tests] {url}", flush=True)

    profile = tempfile.mkdtemp(prefix="nucleant-ui-wasm-tests-")
    # A dark page (prefers-color-scheme), whatever the machine's own setting:
    # the appearance tests expect the app to see dark at launch.
    command = [chrome, f"--user-data-dir={profile}", "--no-first-run", "--no-default-browser-check",
               "--enable-unsafe-webgpu", "--blink-settings=preferredColorScheme=0", "--remote-debugging-port=0", url]
    if not args.headed:
        command.insert(1, "--headless=new")
    browser = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        finished = Handler.done.wait(args.timeout)
    finally:
        browser.terminate()
        try:
            browser.wait(10)
        except subprocess.TimeoutExpired:
            browser.kill()
        server.shutdown()
        shutil.rmtree(profile, ignore_errors=True)
    if not finished:
        print(f"[run_wasm_tests] timed out after {args.timeout:.0f}s", flush=True)
        return 1
    print(f"[run_wasm_tests] exit status {Handler.status}", flush=True)
    return Handler.status


if __name__ == "__main__":
    sys.exit(main())

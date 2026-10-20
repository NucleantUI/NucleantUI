#!/usr/bin/env python3
"""Build the examples for WebAssembly as one shared module and a small module per app.

    python3 Scripts/build_examples_wasm.py [output-dir] [--only Calculator,Tasks] [--serve]

Output defaults to .build/examples-site. Scripts/build-docs.sh calls this with
a directory inside the documentation site, so each example is a page at
/NucleantUI/examples/<Example>/.

Built one by one, each example would be a ~70 MB module of which ~200 KB is
its own code: the rest — the Swift runtime, Foundation (ICU's data alone is
~30 MB), NucleantUI and everything under it — is the same in every one. So
the examples are linked the way a native app links a shared library:

    shared/nucleant-shared.wasm   the main module: everything but the apps,
                                  at fixed addresses, exporting what any of
                                  the apps uses from it
    <Example>/<Example>.wasm      a side module (`wasm-ld -shared`, position
                                  independent): the example's own objects,
                                  importing the rest from the main module

The browser fetches the shared module once and caches it for every example;
NucleantApplication's page runtime (Web/nucleant-app.js, `app` option)
instantiates it, then loads the example against it.

How:

1. A package is generated in .build/examples-wasm with every example as an
   executable target (its sources symlinked from Examples/, its resources
   and the other packages it links from the example's manifest; the shaders
   an example's PyShader build plugin would compile, compiled here by a host
   `pyshaderc` and added as resources), so NucleantUI and what it depends on
   are compiled once, and the main module and every side module are linked
   from the same objects. Each example is built as SwiftPM builds it for
   build_wasm_app.py (a WASI reactor); the link line the driver ran is
   taken from the verbose output.
2. Each example's own objects are linked again as a side module.
3. The main module is the union of the examples' link lines without their
   own objects, exporting the union of what the side modules import.

wasm-ld (LLVM 21, Swift 6.3.3) gets one relocation wrong in side modules:
for R_WASM_MEMORY_ADDR_LOCREL_I32 — the relative pointers all through Swift's
metadata and mangled names — the runtime relocation stores
`__memory_base + (S - P)` where it should leave `S - P`, which the data
already holds. So a side module's data is placed at address 0: the main
module's own data starts above it (--global-base), and with __memory_base 0
that relocation is right. A small zero-filled guard object is linked first,
so no Swift data sits at address 0 itself. A page loads one example, so one
side module ever needs that space.

The modules are shipped gzipped and inflated in the browser (GitHub Pages
serves .wasm uncompressed); the page runtime inflates any `.gz` URL.

Needs a swift.org toolchain and its matching WebAssembly Swift SDK (see
Scripts/build-playground.sh), and NucleantApplication's and NucleantVulkan's
Web/ directories — the sibling checkouts in a development tree, else
SwiftPM's checkouts.
"""

from __future__ import annotations

import argparse
import functools
import gzip
import http.server
import json
import os
import re
import shlex
import shutil
import struct
import subprocess
import sys
from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve().parent.parent
EXAMPLES_DIR = PACKAGE_ROOT / "Examples"
WORK = PACKAGE_ROOT / ".build" / "examples-wasm"
GENERATED = WORK / "package"
SCRATCH = WORK / "build"
VERSION_RE = re.compile(r"(\d+\.\d+(?:\.\d+)?)")

# The examples that run in a browser today. Left out: Metronome and Sampler
# (NucleantAudio has a macOS backend only).
EXAMPLES = [
    "Calculator", "Tasks", "Sketch", "Dashboard", "TwentyFortyEight", "Pomodoro", "Flashcards",
    "AnimatableShader", "Finder", "Photos", "Bookmarks", "Moodboard", "MindMap", "Reader", "Compositor", "Issues",
]
SHARED = "nucleant-shared"
# A WASI reactor, as NucleantApplication's build_wasm_app.py builds an app:
# no _start, `main` exported for the page to call. The 8 MB stack: wasm-ld's
# default 64 KB grows down into the data and corrupts it.
STACK_SIZE = 8 * 1024 * 1024
REACTOR_TOOLSET = {
    "schemaVersion": "1.0",
    "swiftCompiler": {"extraCLIOptions": ["-Xclang-linker", "-mexec-model=reactor"]},
    "linker": {"extraCLIOptions": ["--export=__main_argc_argv", "-z", f"stack-size={STACK_SIZE}"]},
}
# What the page runtime needs from the main module to load a side module
# into it: the table to append the app's functions to, the shadow stack
# both share, and where the main module's own data begins.
SHARED_EXPORTS = ["--export-table", "--growable-table", "--export=__stack_pointer", "--export=__global_base"]
# Kept free below the main module's data for the side module's, at least.
MIN_SIDE_DATA = 1024 * 1024
GUARD_SIZE = 4096
RESOURCES_ROOT = "/app"
NUCLEANT_APPLICATION_WEB = ["nucleant-app.js"]
NUCLEANT_VULKAN_WEB = ["nucleant-webgpu.js", "nucleant-wgpu.js", "nucleant-wasi.js", "naga_webgpu.wasm"]
ZONEINFO = Path("/usr/share/zoneinfo")
ZONEINFO_SKIPPED = {"tzdata.zi", "leapseconds", "leap-seconds.list", "posix", "right"}


def find_wasm_sdk() -> tuple[Path, str]:
    """(toolchain bin directory, SDK id) for the newest installed *_wasm SDK whose toolchain exists."""
    roots = [Path.home() / "Library" / "org.swift.swiftpm" / "swift-sdks", Path.home() / ".swiftpm" / "swift-sdks"]
    for root in roots:
        for bundle in sorted(root.glob("*_wasm.artifactbundle"), reverse=True):
            sdk = bundle.name.removesuffix(".artifactbundle")
            version = VERSION_RE.search(sdk).group(1)
            for base in (Path.home() / "Library" / "Developer" / "Toolchains", Path("/Library/Developer/Toolchains")):
                bin_dir = base / f"swift-{version}-RELEASE.xctoolchain" / "usr" / "bin"
                if (bin_dir / "swift").is_file():
                    return bin_dir, sdk
    sys.exit("error: no wasm Swift SDK with a matching toolchain found")


def sdk_swiftrt(sdk: str) -> Path:
    """The SDK's swiftrt.o: registers an image's metadata sections with the runtime."""
    for root in (Path.home() / "Library" / "org.swift.swiftpm" / "swift-sdks", Path.home() / ".swiftpm" / "swift-sdks"):
        found = list((root / f"{sdk}.artifactbundle").glob("**/swift_static/wasi/wasm32/swiftrt.o"))
        if found:
            return found[0]
    sys.exit(f"error: swiftrt.o not found in {sdk}")


def sibling_web(name: str, marker: str) -> Path:
    """`name`'s Web/ — the sibling checkout in a development tree, else SwiftPM's."""
    for candidate in (PACKAGE_ROOT.parent / name / "Web", SCRATCH / "checkouts" / name / "Web"):
        if (candidate / marker).is_file():
            return candidate
    sys.exit(f"error: {name}'s Web/ directory not found")


# MARK: - The generated package

def example_manifest(bin_dir: Path, name: str) -> tuple[dict, list[dict]]:
    """The example's one target, and its package dependencies, from its manifest."""
    dump = subprocess.run([str(bin_dir / "swift"), "package", "dump-package"], cwd=EXAMPLES_DIR / name,
                          capture_output=True, text=True)
    if dump.returncode != 0:
        sys.exit(f"error: reading Examples/{name}/Package.swift failed:\n{dump.stderr}")
    package = json.loads(dump.stdout)
    targets = package["targets"]
    if len(targets) != 1 or targets[0]["name"] != name or targets[0]["type"] != "executable":
        sys.exit(f"error: Examples/{name} is expected to have one executable target named {name}")
    for dependency in targets[0]["dependencies"]:
        if "product" not in dependency:
            sys.exit(f"error: Examples/{name} depends on {dependency}; only products are supported here")
    return targets[0], package["dependencies"]


def package_dependency(dependency: dict) -> tuple[str, str] | None:
    """(identity, `.package(...)`) for one of an example's dependencies — None
    for NucleantUI, which the generated package takes from this checkout."""
    if "fileSystem" in dependency:
        entry = dependency["fileSystem"][0]
        if entry["identity"] == "nucleantui":
            return None
        return entry["identity"], f".package(path: {json.dumps(entry['path'])})"
    entry = dependency["sourceControl"][0]
    if entry["identity"] == "nucleantui":
        return None
    url = json.dumps(entry["location"]["remote"][0]["urlString"])
    requirement = entry["requirement"]
    if "range" in requirement:
        bounds = requirement["range"][0]
        return entry["identity"], f".package(url: {url}, {json.dumps(bounds['lowerBound'])}..<{json.dumps(bounds['upperBound'])})"
    if "exact" in requirement:
        return entry["identity"], f".package(url: {url}, exact: {json.dumps(requirement['exact'][0])})"
    if "branch" in requirement:
        return entry["identity"], f".package(url: {url}, branch: {json.dumps(requirement['branch'][0])})"
    sys.exit(f"error: unsupported requirement {requirement}")


def pyshader_config(path: Path) -> list[dict]:
    """The sections of a `pyshader.toml`, in order: the subset PyShader reads —
    `[name]` tables of strings, booleans and arrays of strings."""
    def strip_comment(line: str) -> str:
        quote = None
        for index, char in enumerate(line):
            if quote:
                quote = None if char == quote else quote
            elif char in "\"'":
                quote = char
            elif char == "#":
                return line[:index]
        return line

    def value(text: str):
        text = text.strip()
        if text in ("true", "false"):
            return text == "true"
        if text.startswith("["):
            return [a or b for a, b in re.findall(r'"([^"]*)"|\'([^\']*)\'', text)]
        return text[1:-1]

    sections: list[dict] = []
    pending = ""
    for raw in path.read_text().splitlines():
        line = (pending + " " if pending else "") + strip_comment(raw).strip()
        if line.count("[") > line.count("]") and "=" in line:
            pending = line  # an array continuing on the next line
            continue
        pending = ""
        if not line:
            continue
        if line.startswith("[") and "=" not in line:
            sections.append({"name": line[1:-1].strip().strip('"')})
        elif sections:
            key, text = line.split("=", 1)
            sections[-1][key.strip()] = value(text)
    return sections


def host_pyshaderc(bin_dir: Path, dependency: dict) -> Path:
    """`pyshaderc`, built for this Mac from the PyShader an example depends on.

    Not by PyShader's build plugin inside the wasm build: that build runs with
    WASM_BUILD=1, which SpirvTools' manifest reads to leave its macOS library
    out, so the plugin's host tool would not compile there."""
    if "fileSystem" in dependency:
        root = Path(dependency["fileSystem"][0]["path"])
    else:
        host = WORK / "pyshaderc-package"
        host.mkdir(parents=True, exist_ok=True)
        found = package_dependency(dependency)
        assert found, "PyShader is never NucleantUI"
        line = found[1]
        (host / "Package.swift").write_text(
            "// swift-tools-version: 6.2\n// Generated by Scripts/build_examples_wasm.py: resolves PyShader.\n\n"
            "import PackageDescription\n\n"
            f"let package = Package(name: \"PyShaderHost\", dependencies: [{line}], targets: [])\n")
        run = subprocess.run([str(bin_dir / "swift"), "package", "resolve"], cwd=host, capture_output=True, text=True)
        if run.returncode != 0:
            sys.exit(f"error: resolving PyShader failed:\n{run.stderr}")
        root = host / ".build" / "checkouts" / "PyShader"
    scratch = WORK / "pyshaderc-build"
    env = {k: v for k, v in os.environ.items() if k != "WASM_BUILD"}
    print("+ swift build --product pyshaderc -c release (host)", flush=True)
    build = subprocess.run([str(bin_dir / "swift"), "build", "--package-path", str(root), "--scratch-path", str(scratch),
                            "--product", "pyshaderc", "-c", "release"], env=env, capture_output=True, text=True)
    if build.returncode != 0:
        sys.exit(f"error: building pyshaderc failed:\n{build.stdout[-4000:]}{build.stderr[-4000:]}")
    return scratch / "release" / "pyshaderc"


def compile_shaders(pyshaderc: Path, name: str, into: Path) -> list[str]:
    """Each section of the example's `pyshader.toml` compiled into `into`, as
    its build plugin would; the files' names."""
    config = EXAMPLES_DIR / name / "pyshader.toml"
    if not config.is_file():
        sys.exit(f"error: Examples/{name} uses PyShaderBuildPlugin but has no pyshader.toml")
    into.mkdir(parents=True, exist_ok=True)
    outputs = []
    for section in pyshader_config(config):
        output = Path(section.get("output", f"{section['name']}.spv")).name
        args = [str(pyshaderc), str(EXAMPLES_DIR / name / section["source"]), "-o", str(into / output),
                "--target", section.get("target", "fragment")]
        if section.get("content"):
            args.append("--content")
        for flag, key in (("--arg", "arguments"), ("--texture", "textures"), ("--optimize", "optimize")):
            for item in section.get(key, []):
                args += [flag, item]
        run = subprocess.run(args, capture_output=True, text=True)
        if run.returncode != 0:
            sys.exit(f"error: compiling Examples/{name}/{section['source']} failed:\n{run.stderr}")
        outputs.append(output)
    return outputs


def resource_rule(resource: dict, prefix: str = "") -> str:
    path = json.dumps(prefix + resource["path"])
    if "copy" in resource["rule"]:
        return f".copy({path})"
    if "process" in resource["rule"]:
        return f".process({path})"
    sys.exit(f"error: unsupported resource rule {resource}")


def generate_package(bin_dir: Path, names: list[str]) -> None:
    sources = GENERATED / "Sources"
    if sources.exists():
        shutil.rmtree(sources)
    sources.mkdir(parents=True)
    targets = []
    packages: dict[str, str] = {}
    pyshaderc: Path | None = None
    for name in names:
        target, dependencies = example_manifest(bin_dir, name)
        used = {d["product"][1].lower() for d in target["dependencies"]}
        for dependency in dependencies:
            found = package_dependency(dependency)
            # Only what the app links: a package it takes a plugin from is
            # run here, not depended on.
            if found and found[0] in used:
                packages[found[0]] = found[1]
        products = ", ".join(
            f".product(name: {json.dumps(d['product'][0])}, package: {json.dumps(d['product'][1])})"
            for d in target["dependencies"])
        usages = [u["plugin"] for u in target.get("pluginUsages") or []]
        if any(p[0] != "PyShaderBuildPlugin" for p in usages):
            sys.exit(f"error: Examples/{name} uses {usages}; only PyShaderBuildPlugin is supported here")
        if usages:
            # The shaders the plugin would build, compiled here and handed to
            # the target as resources beside its sources, at the bundle's root
            # where the plugin's land.
            if pyshaderc is None:
                pyshader = next(d for d in dependencies
                                if (d.get("fileSystem") or d.get("sourceControl") or [{}])[0].get("identity") == "pyshader")
                pyshaderc = host_pyshaderc(bin_dir, pyshader)
            directory = sources / name
            directory.mkdir()
            (directory / "App").symlink_to(EXAMPLES_DIR / name / "Sources" / name)
            shaders = compile_shaders(pyshaderc, name, directory / "Shaders")
            rules = [resource_rule(r, "App/") for r in target.get("resources") or []]
            rules += [f".copy({json.dumps('Shaders/' + s)})" for s in shaders]
        else:
            (sources / name).symlink_to(EXAMPLES_DIR / name / "Sources" / name)
            rules = [resource_rule(r) for r in target.get("resources") or []]
        resources = ", ".join(rules)
        targets.append(
            f"        .executableTarget(\n"
            f"            name: {json.dumps(name)},\n"
            f"            dependencies: [{products}]"
            + (f",\n            resources: [{resources}]" if resources else "") + "\n        ),")
    package_lines = [f".package(path: {json.dumps(str(PACKAGE_ROOT))})"] + [packages[k] for k in sorted(packages)]
    manifest = (
        "// swift-tools-version: 6.2\n"
        "// Generated by Scripts/build_examples_wasm.py: every example as a target of one\n"
        "// package, so what they share is compiled once.\n\n"
        "import PackageDescription\n\n"
        "let package = Package(\n"
        "    name: \"NucleantUIExamples\",\n"
        "    platforms: [.macOS(.v14), .iOS(.v17)],\n"
        "    dependencies: [\n" + "".join(f"        {line},\n" for line in package_lines) + "    ],\n"
        "    targets: [\n" + "\n".join(targets) + "\n    ]\n)\n")
    path = GENERATED / "Package.swift"
    if not path.exists() or path.read_text() != manifest:
        path.write_text(manifest)


# MARK: - Building

def build_example(bin_dir: Path, sdk: str, name: str) -> list[str]:
    """Builds `name` and returns the driver's link line for it."""
    toolset = SCRATCH / "reactor-toolset.json"
    toolset.write_text(json.dumps(REACTOR_TOOLSET, indent=2))
    # Relinked every time, so the verbose output has the link line.
    (SCRATCH / "release" / f"{name}.wasm").unlink(missing_ok=True)
    command = [str(bin_dir / "swift"), "build", "--swift-sdk", sdk, "--toolset", str(toolset),
               "--scratch-path", str(SCRATCH), "--product", name, "-c", "release", "-v"]
    print(f"+ swift build --product {name} -c release", flush=True)
    process = subprocess.Popen(command, cwd=GENERATED, env=dict(os.environ, WASM_BUILD="1"),
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    link = None
    for line in process.stdout:
        if line.startswith("[") or "error:" in line or "warning: " in line and f"/{name}/" in line:
            print(line.rstrip()[:400], flush=True)
        words = line.split()
        if words and words[0].strip('"').endswith("/clang") and f"/{name}.wasm" in line:
            link = shlex.split(line)
    if process.wait() != 0:
        sys.exit(f"error: building {name} for wasm failed")
    if link is None:
        sys.exit(f"error: no link line for {name} in SwiftPM's verbose output")
    return link


def own_objects(link: list[str], name: str) -> list[str]:
    objects = [a for a in link if a.endswith(".o") and f"/{name}.build/" in a]
    if not objects:
        sys.exit(f"error: no objects of {name} on its link line")
    return objects


def guard_object(bin_dir: Path) -> Path:
    """Zero-filled data linked first into a side module, so none of its data sits at address 0."""
    source = WORK / "side-guard.c"
    source.write_text(f"__attribute__((used, aligned(16))) const char nucleant_side_guard[{GUARD_SIZE}] = {{1}};\n")
    obj = WORK / "side-guard.o"
    subprocess.run([str(bin_dir / "clang"), "--target=wasm32-unknown-wasip1", "-fPIC", "-c", str(source), "-o", str(obj)],
                   check=True)
    return obj


def link_side(bin_dir: Path, swiftrt: Path, guard: Path, objects: list[str], output: Path) -> None:
    command = [str(bin_dir / "wasm-ld"), "-m", "wasm32", "-shared", "--experimental-pic",
               "--unresolved-symbols=import-dynamic", "--strip-debug", str(guard), str(swiftrt), *objects, "-o", str(output)]
    if subprocess.run(command).returncode != 0:
        sys.exit(f"error: linking {output.name} failed")


def link_shared(links: dict[str, list[str]], owned: dict[str, list[str]], exports: list[str],
                global_base: int, output: Path) -> None:
    """The examples' link lines merged, without their own objects or `main`."""
    def strip(name: str) -> list[str]:
        out, args, i = [], links[name], 0
        while i < len(args):
            a = args[i]
            if a in owned[name] or a == "-v":
                i += 1
                continue
            if a == "-Xlinker" and i + 1 < len(args) and args[i + 1] == "--export=__main_argc_argv":
                i += 2
                continue
            if a.startswith("--global-base="):
                a = f"--global-base={global_base}"
            out.append(a)
            i += 1
        return out

    names = list(links)
    merged = strip(names[0])
    for name in names[1:]:
        args = strip(name)
        objects = [a for a in args if a.endswith(".o") and a not in merged]
        if objects:
            last = max(i for i, a in enumerate(merged) if a.endswith(".o"))
            merged[last + 1:last + 1] = objects
        libraries = [a for a in args if a.startswith("-l") and a not in merged]
        merged[merged.index("-o"):merged.index("-o")] = libraries
    merged[merged.index("-o") + 1] = str(output)
    response = WORK / "shared-exports.rsp"
    flags = [*SHARED_EXPORTS, "--strip-debug", *[f"--export={symbol}" for symbol in exports]]
    response.write_text("".join(f"-Xlinker {shlex.quote(flag)}\n" for flag in flags))
    result = subprocess.run([*merged, f"@{response}"], capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"error: linking {output.name} failed:\n{result.stderr[-8000:]}")


# MARK: - Reading wasm modules

def leb(data: bytes, at: int) -> tuple[int, int]:
    result = shift = 0
    while True:
        byte = data[at]
        at += 1
        result |= (byte & 0x7F) << shift
        shift += 7
        if byte < 0x80:
            return result, at


def module_symbols(path: Path) -> tuple[list[tuple[str, str, int]], set[str], int]:
    """(imports as (module, name, kind), export names, dylink.0 memory size)."""
    data = path.read_bytes()
    imports, exports, mem_size = [], set(), 0

    def name(at: int) -> tuple[str, int]:
        length, at = leb(data, at)
        return data[at:at + length].decode(), at + length

    at = 8
    while at < len(data):
        section = data[at]
        size, at = leb(data, at + 1)
        end, cursor = at + size, at
        if section == 0:
            custom, cursor = name(cursor)
            if custom == "dylink.0":
                while cursor < end:
                    kind = data[cursor]
                    length, cursor = leb(data, cursor + 1)
                    if kind == 1:
                        mem_size, _ = leb(data, cursor)
                    cursor += length
        elif section == 2:
            count, cursor = leb(data, cursor)
            for _ in range(count):
                module, cursor = name(cursor)
                field, cursor = name(cursor)
                kind = data[cursor]
                cursor += 1
                if kind == 0:
                    _, cursor = leb(data, cursor)
                elif kind in (1, 2):
                    if kind == 1:
                        cursor += 1
                    flags = data[cursor]
                    _, cursor = leb(data, cursor + 1)
                    if flags & 1:
                        _, cursor = leb(data, cursor)
                elif kind == 3:
                    cursor += 2
                elif kind == 4:
                    _, cursor = leb(data, cursor + 1)
                imports.append((module, field, kind))
        elif section == 7:
            count, cursor = leb(data, cursor)
            for _ in range(count):
                field, cursor = name(cursor)
                _, cursor = leb(data, cursor + 1)
                exports.add(field)
        at = end
    return imports, exports, mem_size


def needed_from_main(side: Path) -> tuple[set[str], int]:
    """Symbols the side module takes from the main module, and its data size."""
    imports, exports, mem_size = module_symbols(side)
    needed = {field for module, field, kind in imports
              if (module == "env" and kind == 0) or module in ("GOT.mem", "GOT.func")}
    return needed - exports, mem_size


# MARK: - The site

def gzip_file(path: Path) -> Path:
    target = path.with_name(path.name + ".gz")
    with path.open("rb") as source, gzip.open(target, "wb", compresslevel=9) as out:
        shutil.copyfileobj(source, out)
    path.unlink()
    return target


def pack_zoneinfo(source: Path = ZONEINFO) -> bytes | None:
    """The time zone database as one file, in the format Web/nucleant-app.js's loadZoneinfo reads."""
    root = source.resolve()
    if not root.is_dir():
        return None
    packed = bytearray()
    for directory, subdirectories, names in os.walk(root):
        subdirectories[:] = sorted(d for d in subdirectories if d not in ZONEINFO_SKIPPED)
        for file_name in sorted(names):
            path = Path(directory) / file_name
            if file_name in ZONEINFO_SKIPPED or not path.is_file():
                continue
            relative = path.relative_to(root).as_posix().encode()
            contents = path.read_bytes()
            packed += struct.pack("<H", len(relative)) + relative + struct.pack("<I", len(contents)) + contents
    return bytes(packed)


def bundle_owner(bundle: str, names: list[str]) -> str | None:
    """The example a `<Package>_<Target>.resources` bundle belongs to, or None for a shared one."""
    target = bundle.removesuffix(".resources").split("_", 1)[-1]
    return target if target in names else None


def lay_out(output: Path, names: list[str], products: Path) -> None:
    shared_dir = output / "shared"
    shared_dir.mkdir(parents=True, exist_ok=True)
    for file_name in NUCLEANT_APPLICATION_WEB:
        shutil.copy2(sibling_web("NucleantApplication", "nucleant-app.js") / file_name, shared_dir / file_name)
    for file_name in NUCLEANT_VULKAN_WEB:
        shutil.copy2(sibling_web("NucleantVulkan", "nucleant-webgpu.js") / file_name, shared_dir / file_name)
    zoneinfo = pack_zoneinfo()
    if zoneinfo is None:
        print(f"warning: no {ZONEINFO} here — formatting a date in a named time zone will trap", flush=True)
    else:
        (shared_dir / "zoneinfo.bin").write_bytes(zoneinfo)

    # Every bundle once, under resources/: NucleantUI's fonts are the same
    # for every example. Each example's resources.json lists the shared
    # bundles and its own.
    resources = output / "resources"
    if resources.exists():
        shutil.rmtree(resources)
    shared_files, own_files = [], {name: [] for name in names}
    for bundle in sorted(products.glob("*.resources")):
        if not bundle.is_dir():
            continue
        shutil.copytree(bundle, resources / bundle.name)
        files = sorted(p.relative_to(resources).as_posix() for p in (resources / bundle.name).rglob("*") if p.is_file())
        owner = bundle_owner(bundle.name, names)
        (own_files[owner] if owner else shared_files).extend(files)

    page = (PACKAGE_ROOT / "Scripts" / "examples-page.html").read_text()
    for name in names:
        directory = output / name
        manifest = {"root": RESOURCES_ROOT, "buildRoot": str(products.resolve()), "base": "../resources/",
                    "files": shared_files + own_files[name]}
        (directory / "resources.json").write_text(json.dumps(manifest, indent=2) + "\n")
        (directory / "index.html").write_text(page.replace("{{EXAMPLE}}", name).replace("{{SHARED}}", SHARED))


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, *args):
        pass


def serve(directory: Path, port: int) -> None:
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), functools.partial(Handler, directory=str(directory)))
    print(f"serving http://127.0.0.1:{server.server_address[1]}/<Example>/  (Ctrl-C to stop)", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


# MARK: - Checking the pages

CHROME_CANDIDATES = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
]
# A laptop's browser window: smaller than some examples' default size, so
# their canvases are fitted to the page while the first frames run.
CHECK_WINDOW = "1024,768"
# Added to each example's page under --check: reports the app starting (a
# window canvas appearing), a failure to start, every error, and whether a
# frame had content. A WebGPU canvas can only be copied in the frame that
# drew it, so the frame is sampled from a frame callback queued behind the
# app's, every frame, until one has more than two colours or 10 s pass.
CHECK_SCRIPT = """<script>
(() => {
  const report = (kind, text) => fetch('/report', { method: 'POST', body: JSON.stringify({ kind, text: String(text) }) });
  const originalError = console.error.bind(console);
  console.error = (...args) => { originalError(...args); report('error', args.map((a) => a instanceof Error ? a.stack || a.message : a).join(' ')); };
  addEventListener('error', (event) => report('error', event.error?.stack || event.message));
  addEventListener('unhandledrejection', (event) => report('error', event.reason?.stack || event.reason));
  const started = performance.now();
  const watch = new MutationObserver(() => {
    const status = document.getElementById('status').textContent;
    if (status.startsWith('Could not start')) { watch.disconnect(); report('failed', status); return; }
    const canvas = document.querySelector('#app canvas');
    if (!canvas) return;
    watch.disconnect();
    report('started', ((performance.now() - started) / 1000).toFixed(1) + ' s');
    const probe = document.createElement('canvas');
    probe.width = probe.height = 64;
    const context = probe.getContext('2d', { willReadFrequently: true });
    const until = performance.now() + 10000;
    const sample = () => {
      context.clearRect(0, 0, 64, 64);
      context.drawImage(canvas, 0, 0, 64, 64);
      const pixels = context.getImageData(0, 0, 64, 64).data;
      const colours = new Set();
      for (let i = 0; i < pixels.length; i += 4) colours.add(pixels[i] << 24 | pixels[i + 1] << 16 | pixels[i + 2] << 8 | pixels[i + 3]);
      if (colours.size > 2) report('rendered', colours.size + ' colours');
      else if (performance.now() > until) report('blank', colours.size + ' colours after 10 s');
      else requestAnimationFrame(sample);
    };
    requestAnimationFrame(() => requestAnimationFrame(sample));
  });
  addEventListener('DOMContentLoaded', () => watch.observe(document.body, { childList: true, subtree: true, characterData: true }));
})();
</script>
"""


def find_chrome() -> str:
    for candidate in [os.environ.get("CHROME"), *CHROME_CANDIDATES]:
        if candidate and Path(candidate).is_file():
            return candidate
    sys.exit("error: --check needs Chrome; set CHROME to its executable")


def check(output: Path, names: list[str], timeout: float = 90) -> bool:
    """Opens every example's page in headless Chrome; true if each started and drew."""
    import queue
    import tempfile
    import threading

    reports: queue.Queue = queue.Queue()

    class CheckHandler(Handler):
        def do_GET(self):
            path = self.path.split("?")[0]
            if path.endswith("/index.html") or path.endswith("/"):
                page = Path(self.translate_path(path if path.endswith(".html") else path + "index.html"))
                if page.is_file():
                    body = page.read_text().replace("<head>", "<head>\n" + CHECK_SCRIPT, 1).encode()
                    self.send_response(200)
                    self.send_header("Content-Type", "text/html; charset=utf-8")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                    return
            super().do_GET()

        def do_POST(self):
            body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
            if self.path == "/report":
                reports.put(json.loads(body))
            self.send_response(204)
            self.end_headers()

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(CheckHandler, directory=str(output)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    chrome = find_chrome()
    passed = True
    try:
        for name in names:
            while not reports.empty():
                reports.get_nowait()
            profile = tempfile.mkdtemp(prefix="nucleant-examples-check-")
            url = f"http://127.0.0.1:{server.server_address[1]}/{name}/index.html"
            browser = subprocess.Popen([chrome, "--headless=new", f"--user-data-dir={profile}", "--no-first-run",
                                        "--no-default-browser-check", "--enable-unsafe-webgpu", f"--window-size={CHECK_WINDOW}",
                                        "--remote-debugging-port=0", url],
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            outcome, detail, errors = "timed out", f"after {timeout:.0f} s", []
            try:
                while True:
                    try:
                        report = reports.get(timeout=timeout)
                    except queue.Empty:
                        break
                    kind, text = report["kind"], report["text"]
                    if kind == "error":
                        errors.append(text)
                    elif kind == "started":
                        detail = f"started in {text}"
                    else:
                        # failed: the page's message; rendered / blank: the sample.
                        outcome, detail = kind, text if kind == "failed" else f"{detail}, {text}"
                        break
            finally:
                browser.terminate()
                try:
                    browser.wait(10)
                except subprocess.TimeoutExpired:
                    browser.kill()
                shutil.rmtree(profile, ignore_errors=True)
            ok = outcome == "rendered" and not errors
            passed &= ok
            print(f"{'ok  ' if ok else 'FAIL'} {name}: {outcome} ({detail})", flush=True)
            for error in errors:
                print(f"     error: {error[:600]}", flush=True)
    finally:
        server.shutdown()
    return passed


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("output", nargs="?", type=Path, default=PACKAGE_ROOT / ".build" / "examples-site")
    parser.add_argument("--only", help="comma-separated examples to build (default: all that run in a browser)")
    parser.add_argument("--serve", action="store_true", help="serve the site afterwards")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--check", action="store_true",
                        help="open every example's page in headless Chrome; fail unless each starts and draws")
    parser.add_argument("--check-only", action="store_true", help="check an existing output directory without building")
    args = parser.parse_args(argv)

    names = args.only.split(",") if args.only else EXAMPLES
    unknown = [n for n in names if not (EXAMPLES_DIR / n / "Package.swift").is_file()]
    if unknown:
        sys.exit(f"error: no such example: {', '.join(unknown)}")
    output = args.output.resolve()
    if args.check_only:
        return 0 if check(output, names) else 1
    bin_dir, sdk = find_wasm_sdk()
    SCRATCH.mkdir(parents=True, exist_ok=True)
    generate_package(bin_dir, names)

    links = {name: build_example(bin_dir, sdk, name) for name in names}
    owned = {name: own_objects(links[name], name) for name in names}

    if output.exists():
        shutil.rmtree(output)
    swiftrt, guard = sdk_swiftrt(sdk), guard_object(bin_dir)
    needed, largest = set(), 0
    for name in names:
        (output / name).mkdir(parents=True)
        side = output / name / f"{name}.wasm"
        link_side(bin_dir, swiftrt, guard, owned[name], side)
        symbols, mem_size = needed_from_main(side)
        needed |= symbols
        largest = max(largest, mem_size)
        print(f"{name}: {side.stat().st_size // 1024} KB, {len(symbols)} symbols from the shared module", flush=True)

    # Above the largest side module's data, on a 64 KB page.
    global_base = max(MIN_SIDE_DATA, (largest + GUARD_SIZE + 0xFFFF) & ~0xFFFF)
    (output / "shared").mkdir(parents=True)
    shared = output / "shared" / f"{SHARED}.wasm"
    link_shared(links, owned, sorted(needed), global_base, shared)
    _, shared_exports, _ = module_symbols(shared)
    missing = sorted(needed - shared_exports)
    if missing:
        sys.exit(f"error: the shared module lacks {len(missing)} symbols the examples use, e.g. {missing[:5]}")
    print(f"{SHARED}.wasm: {shared.stat().st_size // (1024 * 1024)} MB, {len(needed)} symbols exported to the examples",
          flush=True)

    lay_out(output, names, SCRATCH / "release")
    gzip_file(shared)
    for name in names:
        gzip_file(output / name / f"{name}.wasm")
    print(f"examples: {output} (shared {(output / 'shared' / f'{SHARED}.wasm.gz').stat().st_size // (1024 * 1024)} MB gzipped)",
          flush=True)
    if args.check and not check(output, names):
        return 1
    if args.serve:
        serve(output, args.port)
    return 0


if __name__ == "__main__":
    sys.exit(main())

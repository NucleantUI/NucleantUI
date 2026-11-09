"""Compare NucleantUI's animation cost between two commits, on the examples' own interactions.

Builds and launches an example through the run-nucleantui driver with the
framework's existing tracing switched on (`NUCLEANT_TRACE=1` at build time,
`NUCLEANT_SWIFTUI_TRACE_PERF=1` at run time), drives one of the app's own
interactions from outside with synthesized input, and sums up what the passes
logged (`[perf] <kind> <ms> (build <ms>) built=… measured=…`) together with
the process's CPU time over the interaction. Nothing in the framework or the
apps is changed for it.

Debug builds, as the driver makes them: absolute numbers are a debug build's,
so only compare runs against each other.

    uv run --no-project python Scripts/bench_animations.py run <scenario> <label> [--rounds N] [--runs N]
    uv run --no-project python Scripts/bench_animations.py compare <label-a> <label-b>
    uv run --no-project python Scripts/bench_animations.py list

A run launches the app `--runs` times (3) for `--rounds` rounds each (5)
and writes `.build/bench/<label>/<scenario>.json`. To compare two commits:
check out the first, `run` every scenario under one label, check out the
second, `run` them under another, then `compare`.
"""

from __future__ import annotations

import json
import os
import re
import statistics
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DRIVER = ROOT / ".claude/skills/run-nucleantui/driver.sh"
RUN_DIR = ROOT / ".build/run"
BENCH_DIR = ROOT / ".build/bench"

# Seconds left after each input for its animation to finish before the next.
SETTLE = 1.5

# Each scenario: the app, and one round of driver commands. Points are window
# points (title bar included), from the apps at their launch size.
SCENARIOS: dict[str, dict] = {
    "bookmarks-layout": {
        "app": "Bookmarks",
        "about": "Cards ⇄ List: every card moves and resizes to its row (geometry motion)",
        "round": [["click", "353", "132"], ["click", "294", "132"]],
    },
    "bookmarks-tags": {
        "app": "Bookmarks",
        "about": "the sidebar's tags, Cloud ⇄ List (geometry motion)",
        "round": [["click", "196", "217"], ["click", "157", "217"]],
    },
    "flashcards-deal": {
        "app": "Flashcards",
        "about": "a card revealed and graded: thrown off, the next dealt in (transitions: asymmetric scale+opacity, opacity)",
        "round": [["click", "320", "300"], ["click", "450", "510"]],
    },
    "flashcards-card": {
        "app": "Flashcards",
        "about": "the card flipped and back (animatableData), then dragged short and let go (spring-back)",
        "round": [
            ["click", "320", "300"],
            ["click", "320", "300"],
            ["drag", "320", "300", "360", "300"],
        ],
    },
}

PERF = re.compile(
    r"\[perf\] (\S+) ([\d.]+)ms \(build ([\d.]+)ms\) built=(\d+) reused=(\d+) measured=(\d+) text=(\d+)"
)


def driver(*args: str, settle: float | None = None) -> str:
    env = dict(os.environ)
    env["NUCLEANT_TRACE"] = "1"
    env["NUCLEANT_SWIFTUI_TRACE_PERF"] = "1"
    if settle is not None:
        env["SETTLE"] = str(settle)
    done = subprocess.run([str(DRIVER), *args], cwd=ROOT, env=env, capture_output=True, text=True)
    if done.returncode != 0:
        sys.exit(f"driver {' '.join(args)} failed:\n{done.stdout}{done.stderr}")
    return done.stdout


def cpu_seconds(pid: int) -> float:
    """The process's user + system CPU time, from `ps` ([[dd-]hh:]mm:ss.cc)."""
    text = subprocess.run(["ps", "-o", "time=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    days, _, clock = text.rpartition("-")
    parts = [float(p) for p in clock.split(":")]
    seconds = 0.0
    for part in parts:
        seconds = seconds * 60 + part
    return seconds + (float(days) * 86400 if days else 0)


def summarize(lines: list[str]) -> dict:
    passes = []
    for line in lines:
        match = PERF.search(line)
        if match:
            kind, ms, build, built, reused, measured, text = match.groups()
            passes.append({
                "kind": kind, "ms": float(ms), "build": float(build),
                "built": int(built), "measured": int(measured), "text": int(text),
            })
    times = sorted(p["ms"] for p in passes)
    kinds: dict[str, int] = {}
    for p in passes:
        name = p["kind"].split("(")[0]
        kinds[name] = kinds.get(name, 0) + 1
    return {
        "passes": len(passes),
        "kinds": kinds,
        "total_ms": round(sum(times), 1),
        "build_ms": round(sum(p["build"] for p in passes), 1),
        "median_ms": round(statistics.median(times), 2) if times else 0,
        "p95_ms": round(times[int(0.95 * (len(times) - 1))], 2) if times else 0,
        "max_ms": round(times[-1], 2) if times else 0,
        "built": sum(p["built"] for p in passes),
        "measured": sum(p["measured"] for p in passes),
        "text": sum(p["text"] for p in passes),
    }


def forget_build_plan(app: str) -> None:
    """Drop the example's cached build plan (not its build products).

    After the checkout moves to another commit, SwiftPM can keep planning
    with source files that commit doesn't have and fail on "missing
    inputs"; without the plan it plans again and still builds
    incrementally.
    """
    build = ROOT / "Examples" / app / ".build"
    for plan in [build / "debug.yaml", *build.glob("*/debug/description.json")]:
        plan.unlink(missing_ok=True)


def run_once(scenario: str, rounds: int) -> dict:
    """One launch of the app, `rounds` rounds of the interaction, summed up."""
    spec = SCENARIOS[scenario]
    app = spec["app"]
    forget_build_plan(app)
    launched = driver("launch", app)
    found = re.search(r"window \d+ (\d+)", launched)
    if not found:
        sys.exit(f"no window in the driver's answer:\n{launched}")
    pid = int(found.group(1))
    log = RUN_DIR / f"{app}.log"
    time.sleep(2)  # let launch passes finish

    start_bytes = log.stat().st_size
    cpu_before = cpu_seconds(pid)
    wall_before = time.monotonic()
    for _ in range(rounds):
        for step in spec["round"]:
            driver(*step, settle=SETTLE)
    wall = time.monotonic() - wall_before
    cpu = cpu_seconds(pid) - cpu_before

    with log.open(errors="replace") as handle:
        handle.seek(start_bytes)
        lines = handle.read().splitlines()
    driver("quit")
    result = {"cpu_s": round(cpu, 2), "wall_s": round(wall, 1), **summarize(lines)}
    result["cpu_per_pass_ms"] = round(cpu * 1000 / result["passes"], 2) if result["passes"] else 0
    return result


def run(scenario: str, label: str, rounds: int, runs: int) -> None:
    spec = SCENARIOS[scenario]
    commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    print(f"{scenario}: {spec['about']} — {runs} launches × {rounds} rounds at {commit}")
    results = []
    for index in range(runs):
        results.append(run_once(scenario, rounds))
        print(f"  launch {index + 1}: cpu {results[-1]['cpu_s']} s, {results[-1]['passes']} passes, "
              f"{results[-1]['cpu_per_pass_ms']} ms CPU per pass")
    out = BENCH_DIR / label / f"{scenario}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"scenario": scenario, "app": spec["app"], "commit": commit,
                               "rounds": rounds, "runs": results}, indent=2) + "\n")
    print(f"→ {out}")


# Run-to-run spread on one build is about ±6% in CPU per pass (Flashcards,
# three launches of the same commit): judge a change by whether the ranges
# overlap, not by one launch against one.
METRICS = [
    ("cpu_per_pass_ms", "CPU per pass (ms)"),
    ("cpu_s", "CPU time (s)"),
    ("passes", "passes"),
    ("total_ms", "time in passes (ms)"),
    ("build_ms", "  of it building (ms)"),
    ("median_ms", "median pass (ms)"),
    ("p95_ms", "95th percentile pass (ms)"),
    ("max_ms", "slowest pass (ms)"),
    ("built", "nodes built"),
    ("measured", "sizes measured"),
    ("text", "texts measured"),
]


def runs_of(data: dict) -> list[dict]:
    """The launches a result file holds (a single one for older files)."""
    return data["runs"] if "runs" in data else [data]


def compare(a: str, b: str) -> None:
    for path in sorted((BENCH_DIR / a).glob("*.json")):
        other = BENCH_DIR / b / path.name
        if not other.exists():
            print(f"{path.stem}: no run under {b}")
            continue
        x, y = json.loads(path.read_text()), json.loads(other.read_text())
        xs, ys = runs_of(x), runs_of(y)
        print(f"\n{path.stem}  ({a} {x['commit']} → {b} {y['commit']}, "
              f"{len(xs)}/{len(ys)} launches of {x['rounds']}/{y['rounds']} rounds; mean, range)")
        print(f"  {'':28}{a:>22}{b:>22}{'change':>9}")
        for key, name in METRICS:
            cells = []
            means = []
            for runs in (xs, ys):
                values = [r[key] for r in runs if key in r]
                if not values:
                    values = [round(r["cpu_s"] * 1000 / r["passes"], 2) if r["passes"] else 0 for r in runs]
                mean = sum(values) / len(values)
                means.append(mean)
                spread = f" ({min(values):g}–{max(values):g})" if len(values) > 1 else ""
                cells.append(f"{mean:.4g}{spread}")
            change = f"{(means[1] - means[0]) / means[0] * 100:+.0f}%" if means[0] else "—"
            print(f"  {name:28}{cells[0]:>22}{cells[1]:>22}{change:>9}")


def main() -> None:
    args = sys.argv[1:]
    if not args or args[0] == "list":
        for name, spec in SCENARIOS.items():
            print(f"{name:20} {spec['app']:12} {spec['about']}")
        return

    def option(name: str, default: int) -> int:
        return int(args[args.index(name) + 1]) if name in args else default

    if args[0] == "run" and len(args) >= 3:
        run(args[1], args[2], option("--rounds", 5), option("--runs", 3))
        return
    if args[0] == "compare" and len(args) == 3:
        compare(args[1], args[2])
        return
    sys.exit(__doc__)


if __name__ == "__main__":
    main()

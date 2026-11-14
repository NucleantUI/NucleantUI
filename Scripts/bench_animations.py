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
    uv run --no-project python Scripts/bench_animations.py record <label-a> <label-b> --what "…" [--load "…"]
    uv run --no-project python Scripts/bench_animations.py tables
    uv run --no-project python Scripts/bench_animations.py list

A run launches the app `--runs` times (3) for `--rounds` rounds each (5)
and writes `.build/bench/<label>/<scenario>.json`. To compare two commits:
check out the first, `run` every scenario under one label, check out the
second, `run` them under another, then `compare`.

`record` keeps a comparison: it adds the launches of both labels, with
what the change was (`--what`), to the record committed with the plan
(`plans/fable-optimizations/measurements.json`), and writes the tables
again. `tables` writes the tables from the record into the plan's files,
between their `<!-- measurements:… -->` markers: never edit them by hand.
"""

from __future__ import annotations

import datetime
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
PLAN_DIR = ROOT / "plans/fable-optimizations"
RECORD = PLAN_DIR / "measurements.json"
# The plan's files the tables are written into, between their markers.
TABLE_FILES = [PLAN_DIR / "progress.md", PLAN_DIR / "README.md"]

# Seconds left after each input for its animation to finish before the next.
SETTLE = 1.5

# Each scenario: the app, the driver commands that get it there once after
# launch (`setup`, not measured), and one round of driver commands. Points are
# window points (title bar included), from the apps at their launch size.
SCENARIOS: dict[str, dict] = {
    "bookmarks-layout": {
        "app": "Bookmarks",
        "about": "Cards ⇄ List: every card moves and resizes to its row (geometry motion)",
        "round": [["click", "353", "132"], ["click", "294", "132"]],
    },
    "bookmarks-scroll": {
        "app": "Bookmarks",
        "about": "the cards scrolled down and back up (content moving, nothing resized)",
        "round": [["scroll", "600", "500", "-600"], ["scroll", "600", "500", "600"]],
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
    "reader-scroll": {
        "app": "Reader",
        "about": "the first chapter scrolled down and back up (content moving, nothing resized)",
        "setup": [["click", "280", "330"], ["click", "280", "508"]],
        "round": [["scroll", "280", "400", "-600"], ["scroll", "280", "400", "600"]],
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

KEPT = re.compile(r"\bkept=(\d+)")

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
            kept = KEPT.search(line)
            passes.append({
                "kind": kind, "ms": float(ms), "build": float(build),
                "built": int(built), "measured": int(measured), "text": int(text),
                "kept": int(kept.group(1)) if kept else 0,
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
        "kept": sum(p["kept"] for p in passes),
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
    for step in spec.get("setup", []):
        driver(*step, settle=SETTLE)

    start_bytes = log.stat().st_size
    # How busy the machine was: a loaded one makes every pass slower.
    load_start = os.getloadavg()[0]
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
    result = {
        "cpu_s": round(cpu, 2),
        "wall_s": round(wall, 1),
        "load": round((load_start + os.getloadavg()[0]) / 2, 1),
        **summarize(lines),
    }
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


# MARK: - The record

def load_record() -> dict:
    if RECORD.exists():
        return json.loads(RECORD.read_text())
    return {
        "about": "Before/after measurements of the optimization plan, made with "
                 "Scripts/bench_animations.py (`record`). Each holds every launch's "
                 "numbers; the tables in progress.md and README.md are written from "
                 "this file (`tables`).",
        "scenarios": {},
        "measurements": [],
    }


def label_runs(label: str) -> dict[str, dict]:
    """The result files under `label`, by scenario."""
    return {path.stem: json.loads(path.read_text()) for path in sorted((BENCH_DIR / label).glob("*.json"))}


def commit_of(results: dict[str, dict], label: str) -> str:
    commits = {data["commit"] for data in results.values()}
    if len(commits) != 1:
        sys.exit(f"{label}: runs from more than one commit ({', '.join(sorted(commits))})")
    return commits.pop()


def record(a: str, b: str, what: str, load: str | None, date: str | None) -> None:
    before, after = label_runs(a), label_runs(b)
    shared = [name for name in before if name in after]
    if not shared:
        sys.exit(f"no scenario run under both {a} and {b}")
    data = load_record()
    entry = {
        "id": f"{commit_of(before, a)}..{commit_of(after, b)}",
        "date": date or datetime.date.today().isoformat(),
        "what": what,
        "before": commit_of(before, a),
        "after": commit_of(after, b),
        "build": "debug",
        "scenarios": {
            name: {
                "rounds": before[name]["rounds"],
                "before": runs_of(before[name]),
                "after": runs_of(after[name]),
            }
            for name in shared
        },
    }
    if load:
        entry["load"] = load
    for name in shared:
        data["scenarios"][name] = SCENARIOS[name]["about"]
    data["measurements"] = [m for m in data["measurements"] if m["id"] != entry["id"]] + [entry]
    RECORD.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    print(f"recorded {entry['id']} ({', '.join(shared)}) → {RECORD.relative_to(ROOT)}")
    write_tables()


def value(run: dict, key: str) -> float:
    if key == "kept":
        return run.get("kept", 0)
    if key == "build_per_pass_ms":
        return run["build_ms"] / run["passes"] if run["passes"] else 0
    if key == "cpu_per_pass_ms" and key not in run:
        return run["cpu_s"] * 1000 / run["passes"] if run["passes"] else 0
    return run[key]


def stats(runs: list[dict], key: str) -> tuple[float, float, float]:
    values = [value(r, key) for r in runs]
    return sum(values) / len(values), min(values), max(values)


def number(x: float) -> str:
    text = f"{x:.3g}" if abs(x) < 1000 else f"{x:,.0f}"
    return text.replace("-", "−")


def change_cell(before: list[dict], after: list[dict], key: str, unit: str = "") -> str:
    """`before → after (change)`, means of the launches; the change in bold
    when the two sets of launches don't overlap."""
    mean_a, low_a, high_a = stats(before, key)
    mean_b, low_b, high_b = stats(after, key)
    if not mean_a:
        return f"{number(mean_a)} → {number(mean_b)}{unit}"
    change = f"{(mean_b - mean_a) / mean_a * 100:+.0f}%".replace("-", "−")
    if high_b < low_a or low_b > high_a:
        change = f"**{change}**"
    return f"{number(mean_a)} → {number(mean_b)}{unit} ({change})"


def load_of(entry: dict) -> str:
    if "load" in entry:
        return entry["load"]
    loads = [r["load"] for s in entry["scenarios"].values() for r in s["before"] + s["after"] if "load" in r]
    if not loads:
        return "—"
    return f"{min(loads):g}–{max(loads):g}" if min(loads) != max(loads) else f"{loads[0]:g}"


DETAIL_METRICS = [
    ("cpu_per_pass_ms", "CPU per pass", " ms"),
    ("build_per_pass_ms", "building per pass", " ms"),
    ("median_ms", "median pass", " ms"),
    ("p95_ms", "95th percentile pass", " ms"),
    ("max_ms", "slowest pass", " ms"),
    ("passes", "passes for the interaction", ""),
    ("cpu_s", "CPU for the interaction", " s"),
    ("built", "nodes built, all passes", ""),
    ("measured", "sizes measured, all passes", ""),
    ("text", "texts measured, all passes", ""),
    ("kept", "subtrees kept, all passes", ""),
]


def scenario_order(names) -> list[str]:
    known = list(SCENARIOS)
    return sorted(names, key=lambda n: known.index(n) if n in known else len(known))


def summary_table(data: dict) -> str:
    entries = data["measurements"]
    names = scenario_order({n for m in entries for n in m["scenarios"]})
    lines = [
        "CPU per pass, mean of the launches (debug builds); in **bold** where the",
        "launches before and after don't overlap. Written by",
        "`Scripts/bench_animations.py tables` from [measurements.json](measurements.json).",
        "",
        "| Measured | Before → after | Date | Load | " + " | ".join(f"`{n}`" for n in names) + " |",
        "|---|---|---|---|" + "---|" * len(names),
    ]
    for m in entries:
        cells = []
        for n in names:
            s = m["scenarios"].get(n)
            cells.append(change_cell(s["before"], s["after"], "cpu_per_pass_ms", " ms") if s else "")
        lines.append(f"| {m['what']} | `{m['before']}` → `{m['after']}` | {m['date']} | {load_of(m)} | "
                     + " | ".join(cells) + " |")
    return "\n".join(lines)


def details(data: dict) -> str:
    out = []
    for m in data["measurements"]:
        names = scenario_order(m["scenarios"])
        launches = ", ".join(
            f"`{n}` {len(m['scenarios'][n]['before'])}/{len(m['scenarios'][n]['after'])} launches "
            f"of {m['scenarios'][n]['rounds']} rounds" for n in names
        )
        out += [
            f"#### {m['what']}",
            "",
            f"`{m['before']}` → `{m['after']}`, {m['date']}, {m['build']} builds, load {load_of(m)}; {launches}.",
            "",
            "| | " + " | ".join(f"`{n}`" for n in names) + " |",
            "|---|" + "---|" * len(names),
        ]
        for key, name, unit in DETAIL_METRICS:
            cells = [change_cell(m["scenarios"][n]["before"], m["scenarios"][n]["after"], key, unit) for n in names]
            out.append(f"| {name} | " + " | ".join(cells) + " |")
        out.append("")
    return "\n".join(out).rstrip()


def write_tables() -> None:
    data = load_record()
    blocks = {"summary": summary_table(data), "details": details(data)}
    for path in TABLE_FILES:
        text = path.read_text()
        changed = text
        for kind, block in blocks.items():
            start, end = f"<!-- measurements:{kind} -->", f"<!-- /measurements:{kind} -->"
            if start not in changed:
                continue
            head, rest = changed.split(start, 1)
            _, tail = rest.split(end, 1)
            changed = f"{head}{start}\n{block}\n{end}{tail}"
        if changed != text:
            path.write_text(changed)
            print(f"tables → {path.relative_to(ROOT)}")


def main() -> None:
    args = sys.argv[1:]
    if not args or args[0] == "list":
        for name, spec in SCENARIOS.items():
            print(f"{name:20} {spec['app']:12} {spec['about']}")
        return

    def option(name: str, default: int) -> int:
        return int(args[args.index(name) + 1]) if name in args else default

    def text_option(name: str) -> str | None:
        return args[args.index(name) + 1] if name in args else None

    if args[0] == "run" and len(args) >= 3:
        run(args[1], args[2], option("--rounds", 5), option("--runs", 3))
        return
    if args[0] == "compare" and len(args) == 3:
        compare(args[1], args[2])
        return
    if args[0] == "record" and len(args) >= 3 and text_option("--what"):
        record(args[1], args[2], text_option("--what"), text_option("--load"), text_option("--date"))
        return
    if args[0] == "tables":
        write_tables()
        return
    sys.exit(__doc__)


if __name__ == "__main__":
    main()

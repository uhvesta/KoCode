#!/usr/bin/env python3
import argparse
import filecmp
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ARTIFACT_DIR = ROOT / "Scripts" / "e2e-artifacts"
BASELINE_DIR = ROOT / "Tests" / "Snapshots"

CODE_REVIEW_SNAPSHOTS = [
    "codereview-file.png",
    "codereview-file-next-change.png",
    "codereview-diff.png",
]

TERMINAL_SNAPSHOTS = [
    "terminal-before.png",
    "terminal-after-type.png",
    "terminal-after-enter.png",
]


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, cwd=ROOT, check=True)


def run_harnesses(include_terminal: bool) -> list[str]:
    run(["python3", "Scripts/e2e-codereview-harness.py"])
    snapshots = list(CODE_REVIEW_SNAPSHOTS)
    if include_terminal:
        run(["python3", "Scripts/e2e-terminal-harness.py"])
        snapshots.extend(TERMINAL_SNAPSHOTS)
    return snapshots


def update_baselines(names: list[str]) -> None:
    BASELINE_DIR.mkdir(parents=True, exist_ok=True)
    for name in names:
        source = ARTIFACT_DIR / name
        destination = BASELINE_DIR / name
        if not source.exists():
            raise RuntimeError(f"Missing artifact: {source}")
        shutil.copy2(source, destination)
        print(f"updated {destination.relative_to(ROOT)}")


def verify_baselines(names: list[str]) -> bool:
    ok = True
    for name in names:
        actual = ARTIFACT_DIR / name
        expected = BASELINE_DIR / name
        if not expected.exists():
            print(f"missing baseline: {expected.relative_to(ROOT)}", file=sys.stderr)
            ok = False
            continue
        if not actual.exists():
            print(f"missing artifact: {actual.relative_to(ROOT)}", file=sys.stderr)
            ok = False
            continue
        if not filecmp.cmp(actual, expected, shallow=False):
            diff_copy = ARTIFACT_DIR / f"{actual.stem}.actual{actual.suffix}"
            shutil.copy2(actual, diff_copy)
            print(
                f"snapshot mismatch: {name}\n"
                f"  expected: {expected.relative_to(ROOT)}\n"
                f"  actual:   {diff_copy.relative_to(ROOT)}",
                file=sys.stderr,
            )
            ok = False
    return ok


def main() -> int:
    parser = argparse.ArgumentParser(description="Run AvestaCode UI snapshot checks.")
    parser.add_argument("--update", action="store_true", help="Write current captures as baselines.")
    parser.add_argument("--terminal", action="store_true", help="Also snapshot terminal E2E states.")
    args = parser.parse_args()

    names = run_harnesses(include_terminal=args.terminal)
    if args.update:
        update_baselines(names)
        return 0

    if verify_baselines(names):
        print("PASS: UI snapshots match baselines.")
        return 0
    return 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode or 1)
    except Exception as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)

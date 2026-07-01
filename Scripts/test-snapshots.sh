#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MODE=${1:-verify}

cd "$ROOT_DIR"

case "$MODE" in
  verify)
    swift test --filter SnapshotTests
    ;;
  record)
    echo "Recording snapshots. The first test pass is expected to report a record-mode failure."
    SNAPSHOT_TESTING_RECORD=all swift test --filter SnapshotTests || true
    echo "Verifying recorded snapshots."
    swift test --filter SnapshotTests
    ;;
  *)
    echo "usage: Scripts/test-snapshots.sh [verify|record]" >&2
    exit 2
    ;;
esac

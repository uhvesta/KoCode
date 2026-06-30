#!/usr/bin/env python3
import json
import plistlib
import shutil
import subprocess
import sys
import time
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ARTIFACT_DIR = ROOT / "Scripts" / "e2e-artifacts"
APP_PATH = ROOT / ".build" / "release" / "AvestaCode.app"
APP_NAME = "AvestaCode"
SESSION_PATH = Path.home() / "Library" / "Application Support" / "AvestaCode" / "session.json"


def run(cmd: list[str], *, check: bool = True, capture: bool = False) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd,
        cwd=ROOT,
        check=check,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
    )


def osascript(script: str, *, check: bool = True) -> subprocess.CompletedProcess:
    return run(["osascript", "-e", script], check=check, capture=True)


def build_app() -> None:
    run(["sh", "Scripts/build-app.sh", "release"])


def quit_app() -> None:
    osascript(f'tell application "{APP_NAME}" to quit', check=False)
    deadline = time.time() + 5
    while time.time() < deadline:
        proc = osascript(f'tell application "System Events" to exists process "{APP_NAME}"', check=False)
        if "false" in (proc.stdout or "").lower():
            return
        time.sleep(0.2)


def launch_app() -> None:
    run(["open", "-na", str(APP_PATH)])
    deadline = time.time() + 12
    while time.time() < deadline:
        proc = osascript(
            f'tell application "System Events" to tell process "{APP_NAME}" to count windows',
            check=False,
        )
        if (proc.stdout or "").strip().isdigit() and int((proc.stdout or "").strip()) > 0:
            osascript(f'tell application "{APP_NAME}" to activate', check=False)
            time.sleep(0.8)
            return
        time.sleep(0.2)
    raise RuntimeError("AvestaCode launched but did not create a window.")


def screenshot(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    proc = run(["screencapture", "-x", str(path)], check=False, capture=True)
    if proc.returncode != 0:
        raise RuntimeError(proc.stdout or "screencapture failed")


def seed_session(workspace_path: Path) -> Path | None:
    SESSION_PATH.parent.mkdir(parents=True, exist_ok=True)
    backup = None
    if SESSION_PATH.exists():
        backup = SESSION_PATH.with_suffix(f".json.e2e-codereview-backup-{uuid.uuid4().hex}")
        shutil.copy2(SESSION_PATH, backup)

    workspace_path.mkdir(parents=True, exist_ok=True)
    workspace_id = str(uuid.uuid4()).upper()
    tab_id = str(uuid.uuid4()).upper()
    session_id = str(uuid.uuid4()).upper()
    file_id = str(uuid.uuid4()).upper()
    hunk_id = str(uuid.uuid4()).upper()

    def line(kind: str, old: int | None, new: int | None, content: str) -> dict:
        return {
            "id": str(uuid.uuid4()).upper(),
            "kind": kind,
            "oldLineNumber": old,
            "newLineNumber": new,
            "content": content,
        }

    payload = {
        "activeWorkspaceID": workspace_id,
        "cachedRepos": [],
        "globalBoardItems": [],
        "isBoardVisible": False,
        "workspaces": [
            {
                "activeTabID": tab_id,
                "boardItems": [],
                "id": workspace_id,
                "name": "Code Review E2E",
                "path": str(workspace_path),
                "repos": [],
                "tabs": [
                    {
                        "kind": "codeReview",
                        "codeReview": {
                            "id": tab_id,
                            "title": "Code Review",
                            "session": {
                                "id": session_id,
                                "diffSpec": "main...feature/e2e",
                                "repoPath": str(workspace_path),
                                "activeFileIndex": 0,
                                "comments": [],
                                "files": [
                                    {
                                        "id": file_id,
                                        "path": "Sources/Example/RepositoryCoordinator.swift",
                                        "oldPath": None,
                                        "status": "modified",
                                        "hunks": [
                                            {
                                                "id": hunk_id,
                                                "oldStart": 18,
                                                "oldCount": 8,
                                                "newStart": 18,
                                                "newCount": 10,
                                                "lines": [
                                                    line("context", 18, 18, "struct RepositoryCoordinator {"),
                                                    line("context", 19, 19, "    var root: URL"),
                                                    line("removed", 20, None, "    var defaultBranch = \"master\""),
                                                    line("added", None, 20, "    var defaultBranch = \"main\""),
                                                    line("context", 21, 21, ""),
                                                    line("removed", 22, None, "    func clone(_ remote: String) async throws {"),
                                                    line("added", None, 22, "    func clone(_ remote: String, into path: URL) async throws {"),
                                                    line("added", None, 23, "        try await prepareDestination(path)"),
                                                    line("context", 23, 24, "        try await git.clone(remote)"),
                                                    line("context", 24, 25, "    }"),
                                                    line("context", 25, 26, "}"),
                                                ],
                                            }
                                        ],
                                    },
                                    {
                                        "id": str(uuid.uuid4()).upper(),
                                        "path": "Tests/RepositoryCoordinatorTests.swift",
                                        "oldPath": None,
                                        "status": "added",
                                        "hunks": [],
                                    },
                                ],
                            },
                        },
                    }
                ],
            }
        ],
    }
    SESSION_PATH.write_text(json.dumps(payload, indent=2, sort_keys=True))
    return backup


def restore_session(backup: Path | None) -> None:
    if backup is None:
        SESSION_PATH.unlink(missing_ok=True)
    else:
        shutil.move(str(backup), SESSION_PATH)


def main() -> int:
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    workspace_path = Path("/tmp") / f"avestacode_codereview_workspace_{uuid.uuid4().hex[:10]}"
    screenshot_path = ARTIFACT_DIR / "codereview-loaded.png"
    backup = None

    try:
        build_app()
        quit_app()
        backup = seed_session(workspace_path)
        launch_app()
        screenshot(screenshot_path)
    finally:
        quit_app()
        restore_session(backup)

    print(f"PASS: captured code review screen at {screenshot_path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)

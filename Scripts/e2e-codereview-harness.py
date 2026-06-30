#!/usr/bin/env python3
import json
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
            osascript(
                f'tell application "System Events" to tell process "{APP_NAME}" to set frontmost to true',
                check=False,
            )
            time.sleep(1.0)
            front = osascript(
                'tell application "System Events" to get name of first application process whose frontmost is true',
                check=False,
            )
            if (front.stdout or "").strip() == APP_NAME:
                return
        time.sleep(0.2)
    raise RuntimeError("AvestaCode launched but did not become the frontmost window.")


def screenshot(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    rect = avestacode_window_rect()
    proc = run(["screencapture", "-x", f"-R{rect}", str(path)], check=False, capture=True)
    if proc.returncode != 0:
        raise RuntimeError(proc.stdout or "screencapture failed")


def avestacode_window_rect() -> str:
    script = f'''
tell application "System Events"
  tell process "{APP_NAME}"
    if not (exists window 1) then error "No AvestaCode window is available"
    set windowPosition to position of window 1
    set windowSize to size of window 1
    return ((item 1 of windowPosition) as string) & "," & ((item 2 of windowPosition) as string) & "," & ((item 1 of windowSize) as string) & "," & ((item 2 of windowSize) as string)
  end tell
end tell
'''
    proc = osascript(script)
    return (proc.stdout or "").strip()


def click_named_button(name: str) -> None:
    escaped = name.replace('"', '\\"')
    script = f'''
tell application "{APP_NAME}" to activate
delay 0.2
tell application "System Events"
  tell process "{APP_NAME}"
    set frontmost to true
    if not (exists window 1) then error "No AvestaCode window is available"
    try
      click (first button of window 1 whose name is "{escaped}")
    on error
      set windowPosition to position of window 1
      set windowSize to size of window 1
      if "{escaped}" is "Previous Change" then
        set clickX to (item 1 of windowPosition) + 856
        set clickY to (item 2 of windowPosition) + 215
      else if "{escaped}" is "Next Change" then
        set clickX to (item 1 of windowPosition) + 928
        set clickY to (item 2 of windowPosition) + 215
      else if "{escaped}" is "Save Comment" then
        set clickX to (item 1 of windowPosition) + (item 1 of windowSize) - 120
        set clickY to (item 2 of windowPosition) + 194
      else if "{escaped}" is "Send to Board" then
        set clickX to (item 1 of windowPosition) + (item 1 of windowSize) - 156
        set clickY to (item 2 of windowPosition) + 132
      else if "{escaped}" is "Diff" then
        set clickX to (item 1 of windowPosition) + (item 1 of windowSize) - 60
        set clickY to (item 2 of windowPosition) + 138
      else
        error "No fallback coordinates for {escaped}"
      end if
      click at {{clickX, clickY}}
    end try
  end tell
end tell
'''
    osascript(script)
    time.sleep(0.5)


def click_window_point(x_offset: int, y_offset: int) -> None:
    script = f'''
tell application "{APP_NAME}" to activate
delay 0.2
tell application "System Events"
  tell process "{APP_NAME}"
    set frontmost to true
    if not (exists window 1) then error "No AvestaCode window is available"
    set windowPosition to position of window 1
    click at {{(item 1 of windowPosition) + {x_offset}, (item 2 of windowPosition) + {y_offset}}}
  end tell
end tell
'''
    osascript(script)
    time.sleep(0.4)


def type_text(text: str) -> None:
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    script = f'''
tell application "{APP_NAME}" to activate
delay 0.2
tell application "System Events"
  tell process "{APP_NAME}"
    set frontmost to true
    keystroke "{escaped}"
  end tell
end tell
'''
    osascript(script)
    time.sleep(0.4)


def select_tab(index: int) -> None:
    script = f'''
tell application "{APP_NAME}" to activate
delay 0.2
tell application "System Events"
  tell process "{APP_NAME}"
    set frontmost to true
    keystroke "{index}" using command down
  end tell
end tell
'''
    osascript(script)
    time.sleep(0.8)


def menu_shortcut(key: str, modifiers: list[str]) -> None:
    using = ", ".join(f"{modifier} down" for modifier in modifiers)
    script = f'''
tell application "{APP_NAME}" to activate
delay 0.2
tell application "System Events"
  tell process "{APP_NAME}"
    set frontmost to true
    keystroke "{key}" using {{{using}}}
  end tell
end tell
'''
    osascript(script)
    time.sleep(0.8)


def line(kind: str, old: int | None, new: int | None, content: str) -> dict:
    return {
        "id": str(uuid.uuid4()).upper(),
        "kind": kind,
        "oldLineNumber": old,
        "newLineNumber": new,
        "content": content,
    }


def parse_git_diff(base: str) -> list[dict]:
    diff = run(
        ["git", "diff", "--no-ext-diff", "--find-renames", "--unified=40", base],
        capture=True,
    ).stdout or ""
    files: list[dict] = []
    current: dict | None = None
    current_hunk: dict | None = None
    old_line = 0
    new_line = 0

    for raw in diff.splitlines():
        if raw.startswith("diff --git "):
            current = None
            current_hunk = None
            parts = raw.split(" ")
            if len(parts) >= 4:
                path = parts[3][2:] if parts[3].startswith("b/") else parts[3]
                current = {
                    "id": str(uuid.uuid4()).upper(),
                    "path": path,
                    "oldPath": None,
                    "status": "modified",
                    "hunks": [],
                }
                files.append(current)
            continue

        if current is None:
            continue

        if raw.startswith("new file mode"):
            current["status"] = "added"
        elif raw.startswith("deleted file mode"):
            current["status"] = "deleted"
        elif raw.startswith("rename from "):
            current["oldPath"] = raw.removeprefix("rename from ")
            current["status"] = "renamed"
        elif raw.startswith("rename to "):
            current["path"] = raw.removeprefix("rename to ")
        elif raw.startswith("@@ "):
            header = raw.split("@@", 2)[0:2]
            ranges = raw.split(" ")
            old_range = ranges[1][1:]
            new_range = ranges[2][1:]
            old_start, old_count = parse_range(old_range)
            new_start, new_count = parse_range(new_range)
            old_line = old_start
            new_line = new_start
            current_hunk = {
                "id": str(uuid.uuid4()).upper(),
                "oldStart": old_start,
                "oldCount": old_count,
                "newStart": new_start,
                "newCount": new_count,
                "lines": [],
            }
            current["hunks"].append(current_hunk)
        elif current_hunk is not None:
            if raw.startswith(" ") or raw == "":
                content = raw[1:] if raw.startswith(" ") else ""
                current_hunk["lines"].append(line("context", old_line, new_line, content))
                old_line += 1
                new_line += 1
            elif raw.startswith("+") and not raw.startswith("+++"):
                current_hunk["lines"].append(line("added", None, new_line, raw[1:]))
                new_line += 1
            elif raw.startswith("-") and not raw.startswith("---"):
                current_hunk["lines"].append(line("removed", old_line, None, raw[1:]))
                old_line += 1

    return files


def parse_range(value: str) -> tuple[int, int]:
    if "," not in value:
        return int(value), 1
    start, count = value.split(",", 1)
    return int(start), int(count)


def seed_session(repo_path: Path) -> Path | None:
    SESSION_PATH.parent.mkdir(parents=True, exist_ok=True)
    backup = None
    if SESSION_PATH.exists():
        backup = SESSION_PATH.with_suffix(f".json.e2e-codereview-backup-{uuid.uuid4().hex}")
        shutil.copy2(SESSION_PATH, backup)

    workspace_id = str(uuid.uuid4()).upper()
    code_review_tab_id = str(uuid.uuid4()).upper()
    terminal_tab_id = str(uuid.uuid4()).upper()
    session_id = str(uuid.uuid4()).upper()
    files = parse_git_diff("origin/main")
    active_file_index = next(
        (
            index for index, file in enumerate(files)
            if changed_region_count(file) > 1 and is_readable_text_file(ROOT / file["path"])
        ),
        next(
            (
                index for index, file in enumerate(files)
                if file.get("hunks", []) and is_readable_text_file(ROOT / file["path"])
            ),
            0,
        ),
    )

    payload = {
        "activeWorkspaceID": workspace_id,
        "cachedRepos": [],
        "globalBoardItems": [],
        "isBoardVisible": True,
        "workspaces": [
            {
                "activeTabID": code_review_tab_id,
                "boardItems": [],
                "id": workspace_id,
                "name": "AvestaCode Diff",
                "path": str(repo_path),
                "repos": [],
                "tabs": [
                    {
                        "kind": "codeReview",
                        "codeReview": {
                            "id": code_review_tab_id,
                            "title": "Code Review",
                            "session": {
                                "id": session_id,
                                "diffSpec": "origin/main",
                                "repoPath": str(repo_path),
                                "activeFileIndex": active_file_index,
                                "comments": [],
                                "files": files,
                            },
                        },
                    },
                    {
                        "kind": "terminal",
                        "terminal": {
                            "id": terminal_tab_id,
                            "title": "Terminal",
                            "workingDirectory": str(repo_path),
                            "resume": None,
                        },
                    }
                ],
            }
        ],
    }
    SESSION_PATH.write_text(json.dumps(payload, indent=2, sort_keys=True))
    return backup


def load_session() -> dict:
    return json.loads(SESSION_PATH.read_text())


def active_workspace(payload: dict) -> dict:
    active_id = payload["activeWorkspaceID"]
    for workspace in payload["workspaces"]:
        if workspace["id"] == active_id:
            return workspace
    raise RuntimeError("No active workspace in session")


def active_code_review_session(payload: dict) -> dict:
    workspace = active_workspace(payload)
    for tab in workspace["tabs"]:
        if tab.get("kind") == "codeReview":
            return tab["codeReview"]["session"]
    raise RuntimeError("No code review tab in session")


def assert_comment_and_board(comment_text: str) -> None:
    payload = load_session()
    workspace = active_workspace(payload)
    session = active_code_review_session(payload)
    comments = session.get("comments", [])
    if not any(comment.get("text") == comment_text for comment in comments):
        raise RuntimeError(f"Comment was not persisted: {comments}")
    board_items = workspace.get("boardItems", [])
    if not board_items:
        raise RuntimeError("Code review was not sent to board")
    content = board_items[0].get("content", "")
    if comment_text not in content:
        raise RuntimeError("Board item does not contain the saved comment")


def is_readable_text_file(path: Path) -> bool:
    try:
        path.read_text(encoding="utf-8")
        return True
    except OSError:
        return False
    except UnicodeDecodeError:
        return False


def changed_region_count(file: dict) -> int:
    numbers: list[int] = []
    for hunk in file.get("hunks", []):
        for diff_line in hunk.get("lines", []):
            if diff_line.get("kind") == "context":
                continue
            number = diff_line.get("newLineNumber")
            if number is not None:
                numbers.append(number)

    if not numbers:
        return 0

    numbers.sort()
    count = 1
    previous = numbers[0]
    for number in numbers[1:]:
        if number != previous + 1:
            count += 1
        previous = number
    return count


def restore_session(backup: Path | None) -> None:
    if backup is None:
        SESSION_PATH.unlink(missing_ok=True)
    else:
        shutil.move(str(backup), SESSION_PATH)


def main() -> int:
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    file_screenshot_path = ARTIFACT_DIR / "codereview-file.png"
    file_next_screenshot_path = ARTIFACT_DIR / "codereview-file-next-change.png"
    diff_screenshot_path = ARTIFACT_DIR / "codereview-diff.png"
    comment_screenshot_path = ARTIFACT_DIR / "codereview-comment.png"
    board_screenshot_path = ARTIFACT_DIR / "codereview-board.png"
    terminal_paste_screenshot_path = ARTIFACT_DIR / "codereview-board-to-terminal.png"
    latest_screenshot_path = ARTIFACT_DIR / "codereview-loaded.png"
    comment_text = "E2E inline comment: prefer a clearer notification path."
    backup = None

    try:
        build_app()
        quit_app()
        backup = seed_session(ROOT)
        launch_app()
        screenshot(file_screenshot_path)
        shutil.copy2(file_screenshot_path, latest_screenshot_path)
        click_named_button("Next Change")
        screenshot(file_next_screenshot_path)
        click_named_button("Previous Change")
        click_window_point(1000, 515)
        screenshot(comment_screenshot_path)
        click_window_point(1780, 205)
        type_text(comment_text)
        click_named_button("Save Comment")
        click_named_button("Send to Board")
        screenshot(board_screenshot_path)
        click_named_button("Diff")
        screenshot(diff_screenshot_path)
        assert_comment_and_board(comment_text)
        select_tab(2)
        menu_shortcut("v", ["command", "shift"])
        screenshot(terminal_paste_screenshot_path)
    finally:
        quit_app()
        restore_session(backup)

    print(f"PASS: captured code review file screen at {file_screenshot_path}")
    print(f"PASS: captured code review next-change screen at {file_next_screenshot_path}")
    print(f"PASS: captured code review comment screen at {comment_screenshot_path}")
    print(f"PASS: captured code review board screen at {board_screenshot_path}")
    print(f"PASS: captured code review diff screen at {diff_screenshot_path}")
    print(f"PASS: captured board-to-terminal screen at {terminal_paste_screenshot_path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)

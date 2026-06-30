#!/usr/bin/env python3
import argparse
import html
import json
import os
import plistlib
import shutil
import subprocess
import sys
import time
import uuid
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ARTIFACT_DIR = ROOT / "Scripts" / "e2e-artifacts"
APP_PATH = ROOT / ".build" / "release" / "AvestaCode.app"
APP_NAME = "AvestaCode"
SESSION_PATH = Path.home() / "Library" / "Application Support" / "AvestaCode" / "session.json"


@dataclass
class HarnessResult:
    ok: bool
    token: str
    marker_path: Path
    before_screenshot: Path
    after_type_screenshot: Path
    after_enter_screenshot: Path
    report_path: Path
    message: str


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


def seed_terminal_session(workspace_path: Path) -> Path | None:
    SESSION_PATH.parent.mkdir(parents=True, exist_ok=True)
    backup = None
    if SESSION_PATH.exists():
        backup = SESSION_PATH.with_suffix(f".json.e2e-backup-{uuid.uuid4().hex}")
        shutil.copy2(SESSION_PATH, backup)

    workspace_path.mkdir(parents=True, exist_ok=True)
    workspace_id = str(uuid.uuid4()).upper()
    tab_id = str(uuid.uuid4()).upper()
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
                "name": "E2E Terminal",
                "path": str(workspace_path),
                "repos": [],
                "tabs": [
                    {
                        "kind": "terminal",
                        "terminal": {
                            "id": tab_id,
                            "resume": None,
                            "title": "Terminal",
                            "workingDirectory": str(workspace_path),
                        },
                    }
                ],
            }
        ],
    }
    SESSION_PATH.write_text(json.dumps(payload, indent=2, sort_keys=True))
    return backup


def restore_terminal_session(backup: Path | None) -> None:
    if backup is None:
        SESSION_PATH.unlink(missing_ok=True)
        return
    SESSION_PATH.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(backup), SESSION_PATH)


def bundle_identifier() -> str:
    info_path = APP_PATH / "Contents" / "Info.plist"
    with info_path.open("rb") as handle:
        info = plistlib.load(handle)
    return info["CFBundleIdentifier"]


def quit_app() -> None:
    osascript(f'tell application "{APP_NAME}" to quit', check=False)
    deadline = time.time() + 5
    while time.time() < deadline:
        proc = osascript(
            f'tell application "System Events" to exists process "{APP_NAME}"',
            check=False,
        )
        if "false" in (proc.stdout or "").lower():
            return
        time.sleep(0.2)


def launch_app() -> None:
    run(["open", "-na", str(APP_PATH)])
    deadline = time.time() + 10
    while time.time() < deadline:
        proc = osascript(
            f'tell application "System Events" to exists process "{APP_NAME}"',
            check=False,
        )
        if "true" in (proc.stdout or "").lower():
            break
        time.sleep(0.2)
    osascript(f'tell application "{APP_NAME}" to activate', check=False)
    deadline = time.time() + 10
    while time.time() < deadline:
        proc = osascript(
            f'tell application "System Events" to tell process "{APP_NAME}" to count windows',
            check=False,
        )
        if (proc.stdout or "").strip().isdigit() and int((proc.stdout or "").strip()) > 0:
            return
        time.sleep(0.2)
    raise RuntimeError("AvestaCode launched but did not create a window.")


def check_accessibility_permission() -> None:
    probe = osascript(
        'tell application "System Events" to count processes',
        check=False,
    )
    output = probe.stdout or ""
    if probe.returncode != 0:
        raise RuntimeError(
            "macOS blocked UI scripting. Open System Settings > Privacy & Security > Accessibility "
            "and enable the app running this harness, then rerun.\n\n"
            f"Raw error:\n{output}"
        )


def screenshot(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    proc = run(["screencapture", "-x", str(path)], check=False, capture=True)
    if proc.returncode != 0:
        path.with_suffix(path.suffix + ".txt").write_text(proc.stdout or "screencapture failed")


def click_terminal_area() -> None:
    script = f'''
tell application "{APP_NAME}" to activate
delay 0.2
tell application "System Events"
  tell process "{APP_NAME}"
    set frontmost to true
    if not (exists window 1) then error "No AvestaCode window is available"
    set windowPosition to position of window 1
    set windowSize to size of window 1
    set clickX to (item 1 of windowPosition) + ((item 1 of windowSize) div 2)
    set clickY to (item 2 of windowPosition) + ((item 2 of windowSize) div 2)
    click at {{clickX, clickY}}
  end tell
end tell
'''
    osascript(script)
    time.sleep(0.2)


def type_text(text: str) -> None:
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    script = f'''
tell application "{APP_NAME}" to activate
tell application "System Events"
  tell process "{APP_NAME}"
    set frontmost to true
    keystroke "{escaped}"
  end tell
end tell
'''
    osascript(script)


def press_enter() -> None:
    script = f'''
tell application "{APP_NAME}" to activate
tell application "System Events"
  tell process "{APP_NAME}"
    set frontmost to true
    key code 36
  end tell
end tell
'''
    osascript(script)


def wait_for_marker(marker_path: Path, token: str, timeout: float = 5.0) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            if marker_path.read_text().strip() == token:
                return True
        except OSError:
            pass
        time.sleep(0.1)
    return False


def write_report(result: HarnessResult) -> None:
    def img(path: Path) -> str:
        return f'<figure><figcaption>{html.escape(path.name)}</figcaption><img src="{path.name}" /></figure>'

    status = "PASS" if result.ok else "FAIL"
    report = f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <title>AvestaCode Terminal E2E Harness</title>
  <style>
    body {{ font: 14px -apple-system, BlinkMacSystemFont, sans-serif; background: #101214; color: #f5f5f5; padding: 24px; }}
    code, pre {{ font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }}
    .status {{ font-size: 18px; font-weight: 700; }}
    .pass {{ color: #5ee38a; }}
    .fail {{ color: #ff6b6b; }}
    .grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(360px, 1fr)); gap: 16px; }}
    figure {{ margin: 0; padding: 12px; border: 1px solid rgba(255,255,255,.12); border-radius: 8px; background: rgba(255,255,255,.04); }}
    figcaption {{ margin-bottom: 8px; color: rgba(255,255,255,.72); }}
    img {{ width: 100%; border-radius: 6px; border: 1px solid rgba(255,255,255,.12); }}
  </style>
</head>
<body>
  <div class="status {'pass' if result.ok else 'fail'}">{status}</div>
  <p>{html.escape(result.message)}</p>
  <pre>token: {html.escape(result.token)}
marker: {html.escape(str(result.marker_path))}
bundle: {html.escape(str(APP_PATH))}</pre>
  <div class="grid">
    {img(result.before_screenshot)}
    {img(result.after_type_screenshot)}
    {img(result.after_enter_screenshot)}
  </div>
</body>
</html>
"""
    result.report_path.write_text(report)


def run_harness(open_report: bool) -> HarnessResult:
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    token = f"AVESTA_E2E_{uuid.uuid4().hex[:10]}"
    marker_path = Path("/tmp") / f"avestacode_terminal_{token}.txt"
    workspace_path = Path("/tmp") / f"avestacode_terminal_workspace_{token}"
    before = ARTIFACT_DIR / "terminal-before.png"
    after_type = ARTIFACT_DIR / "terminal-after-type.png"
    after_enter = ARTIFACT_DIR / "terminal-after-enter.png"
    report = ARTIFACT_DIR / "terminal-e2e-report.html"
    marker_path.unlink(missing_ok=True)

    backup = None
    check_accessibility_permission()
    try:
        build_app()
        quit_app()
        backup = seed_terminal_session(workspace_path)
        launch_app()
        click_terminal_area()
        screenshot(before)

        command = f"printf {token} > {marker_path}"
        type_text(command)
        time.sleep(0.4)
        screenshot(after_type)
        press_enter()
        ok = wait_for_marker(marker_path, token)
        time.sleep(0.4)
        screenshot(after_enter)
    finally:
        quit_app()
        restore_terminal_session(backup)

    message = (
        "Terminal accepted typed input and executed the marker command."
        if ok
        else "Terminal did not execute the marker command. Check Accessibility permission for UI scripting and inspect screenshots."
    )
    result = HarnessResult(
        ok=ok,
        token=token,
        marker_path=marker_path,
        before_screenshot=before,
        after_type_screenshot=after_type,
        after_enter_screenshot=after_enter,
        report_path=report,
        message=message,
    )
    write_report(result)

    if open_report:
        run(["open", str(report)], check=False)

    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Run AvestaCode terminal UI smoke test.")
    parser.add_argument("--open-report", action="store_true", help="Open the generated HTML screenshot report.")
    args = parser.parse_args()

    try:
        result = run_harness(open_report=args.open_report)
    except RuntimeError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as error:
        output = error.stdout or ""
        if "not allowed assistive access" in output.lower() or "not authorized" in output.lower():
            print("FAIL: macOS blocked UI scripting. Grant Accessibility permission to Terminal/Codex/Xcode, then rerun.", file=sys.stderr)
        print(output, file=sys.stderr)
        return error.returncode or 1

    print(("PASS" if result.ok else "FAIL") + f": {result.message}")
    print(f"Report: {result.report_path}")
    return 0 if result.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

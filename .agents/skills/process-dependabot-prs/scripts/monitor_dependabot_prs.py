#!/usr/bin/env python3
"""Continuously polls GitHub for new or updated open Dependabot pull requests.

State file format:
  A JSON object mapping open PR number strings (e.g. `"4301"`) to their last
  notified state token (`"<headRefOid>:<CLEAN|CONFLICTING>"`).

Usage:
  ./.agents/skills/process-dependabot-prs/scripts/monitor_dependabot_prs.py \\
      "<conversation_id>"

Triggering an immediate poll cycle:
  kill -USR1 <PID>
"""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import pathlib
import signal
import subprocess
import sys
import threading
import traceback
from collections.abc import Mapping, Sequence
from datetime import datetime

_POLL_TRIGGER = threading.Event()
_REPO = "bazel-contrib/rules_python"
_DEPENDABOT_AUTHOR = "app/dependabot"
# Poll once every 5 hours (18,000 seconds) by default; immediate checks after a
# PR merges can be triggered via SIGUSR1.
_DEFAULT_INTERVAL_SECONDS = 5 * 60 * 60
_SKILL_DIR = pathlib.Path(__file__).resolve().parent.parent
_SCRATCH_DIR = _SKILL_DIR / "scratch"
_STATE_FILE = _SCRATCH_DIR / "monitored_dependabot_prs.json"
_LOCK_FILE = _SCRATCH_DIR / ".monitor_dependabot_prs.lock"


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    """Parses command-line arguments."""
    parser = argparse.ArgumentParser(
        description=(
            "Continuously monitor open Dependabot PRs and notify an agent "
            "conversation when new or updated PRs appear."
        ),
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "conv_id",
        help="Conversation ID to notify via agentapi when PRs need processing.",
    )
    parser.add_argument(
        "--interval",
        type=int,
        default=_DEFAULT_INTERVAL_SECONDS,
        help="Polling interval in seconds.",
    )
    return parser.parse_args(argv)


def handle_wakeup_signal(signum: int, unused_frame: object) -> None:
    """Triggers an immediate polling iteration upon receiving SIGUSR1."""
    sig_name = signal.Signals(signum).name
    print(
        f"\n[Signal] Received {sig_name} ({signum}), triggering immediate poll...",
        flush=True,
    )
    _POLL_TRIGGER.set()


def register_signal_handlers() -> None:
    """Registers SIGUSR1 for asynchronous poll wakeups."""
    signal.signal(signal.SIGUSR1, handle_wakeup_signal)


def format_subprocess_output(stdout: str, stderr: str) -> str:
    """Formats captured subprocess stdout and stderr with standard delimiters."""
    return (
        "==================== STDOUT BEGIN ====================\n"
        f"{stdout}\n"
        "==================== STDOUT END ====================\n"
        "==================== STDERR BEGIN ====================\n"
        f"{stderr}\n"
        "==================== STDERR END ===================="
    )


def fetch_open_dependabot_prs() -> list[dict[str, object]]:
    """Queries GitHub for currently open Dependabot pull requests."""
    cmd = [
        "gh",
        "pr",
        "list",
        "--repo",
        _REPO,
        "--author",
        _DEPENDABOT_AUTHOR,
        "--state",
        "open",
        "--json",
        "number,title,url,headRefName,headRefOid,mergeable,mergeStateStatus",
    ]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        e.add_note(format_subprocess_output(e.stdout or "", e.stderr or ""))
        raise
    return json.loads(res.stdout)


def load_seen_state() -> dict[str, str]:
    """Loads the mapping of PR number strings to state tokens from disk."""
    if not _STATE_FILE.exists():
        return {}
    with _STATE_FILE.open(encoding="utf-8") as f:
        data = json.load(f)
    return {str(k): str(v) for k, v in data.items()}


def save_seen_state(seen: Mapping[str, str]) -> None:
    """Writes the mapping of PR number strings to state tokens to disk."""
    _STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    with _STATE_FILE.open("w", encoding="utf-8") as f:
        json.dump(dict(sorted(seen.items())), f, indent=2)
        f.write("\n")


def compute_pr_state_token(pr: Mapping[str, object]) -> str:
    """Computes a state token capturing the PR's head SHA and conflict status."""
    head_oid = str(pr["headRefOid"])
    is_conflicting = (
        pr.get("mergeable") == "CONFLICTING" or pr.get("mergeStateStatus") == "DIRTY"
    )
    conflict_status = "CONFLICTING" if is_conflicting else "CLEAN"
    return f"{head_oid}:{conflict_status}"


def select_actionable_prs(
    open_prs: Sequence[Mapping[str, object]],
    seen: Mapping[str, str],
) -> tuple[list[Mapping[str, object]], dict[str, str]]:
    """Identifies new or updated PRs and returns the updated state dictionary."""
    actionable: list[Mapping[str, object]] = []
    updated_seen: dict[str, str] = {}
    for pr in open_prs:
        pr_num = str(pr["number"])
        token = compute_pr_state_token(pr)
        updated_seen[pr_num] = token
        if seen.get(pr_num) != token:
            actionable.append(pr)
    return actionable, updated_seen


def notify_conversation(conv_id: str, title: str, message: str) -> None:
    """Sends a high-priority notification message to the target conversation."""
    cmd = ["agentapi", "send-message", f"--title={title}", conv_id, message]
    try:
        subprocess.run(cmd, capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        e.add_note(format_subprocess_output(e.stdout or "", e.stderr or ""))
        raise


def format_notification_message(prs: Sequence[Mapping[str, object]]) -> str:
    """Builds the notification message listing new or updated Dependabot PRs."""
    lines = [
        f"🔔 Detected {len(prs)} new or updated open Dependabot PR(s):",
        "",
    ]
    for pr in prs:
        number = pr["number"]
        title = pr["title"]
        url = pr["url"]
        head_oid = str(pr["headRefOid"])[:8]
        merge_state = pr.get("mergeStateStatus", "UNKNOWN")
        lines.append(
            f"- #{number}: {title} ({url}) [SHA: `{head_oid}`, mergeStateStatus: `{merge_state}`]"
        )
    lines.extend(
        [
            "",
            "Action required: Run the `process-dependabot-prs` workflow on the "
            "above PR(s).",
        ]
    )
    return "\n".join(lines)


def poll_once(conv_id: str) -> int:
    """Executes one polling cycle and returns the count of newly notified PRs."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    open_prs = fetch_open_dependabot_prs()
    seen = load_seen_state()
    actionable, updated_seen = select_actionable_prs(open_prs, seen)

    if not actionable:
        save_seen_state(updated_seen)
        print(
            f"[{timestamp}] {len(open_prs)} open Dependabot PR(s); 0 new or updated.",
            flush=True,
        )
        return 0

    msg = format_notification_message(actionable)
    notify_conversation(conv_id, "Dependabot PRs Ready", msg)
    save_seen_state(updated_seen)
    print(
        f"[{timestamp}] Notified conversation {conv_id} about {len(actionable)} "
        "Dependabot PR(s).",
        flush=True,
    )
    return len(actionable)


def main(argv: Sequence[str] | None = None) -> None:
    """Main entrypoint for the continuous Dependabot PR monitor daemon."""
    args = parse_args(argv)
    _SCRATCH_DIR.mkdir(parents=True, exist_ok=True)

    with _LOCK_FILE.open("a+", encoding="utf-8") as lock_file:
        try:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            print(
                "ℹ️ Continuous Dependabot PR monitor is already running in "
                "another process. Exiting.",
                flush=True,
            )
            sys.exit(0)

        lock_file.seek(0)
        lock_file.truncate(0)
        lock_file.write(
            json.dumps({"pid": os.getpid(), "notify_conv_id": args.conv_id}) + "\n"
        )
        lock_file.flush()

        register_signal_handlers()
        pid = os.getpid()
        print(
            f"🚀 Starting continuous Dependabot PR monitor (PID: {pid}) for "
            f"conversation {args.conv_id} every {args.interval}s...",
            flush=True,
        )
        print(f"To trigger an immediate poll: kill -USR1 {pid}", flush=True)

        error_notified = False
        while True:
            woke_by_signal = _POLL_TRIGGER.is_set()
            _POLL_TRIGGER.clear()
            if woke_by_signal:
                error_notified = False
            try:
                poll_once(args.conv_id)
                error_notified = False
            except (
                subprocess.CalledProcessError,
                OSError,
                json.JSONDecodeError,
            ) as e:
                timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                details = "".join(traceback.format_exception_only(e)).strip()
                print(
                    f"[{timestamp}] Warning: Dependabot poll failed: {details}",
                    file=sys.stderr,
                    flush=True,
                )
                if not error_notified:
                    try:
                        notify_conversation(
                            args.conv_id,
                            "Dependabot Monitor Error",
                            "⚠️ Dependabot PR monitor poll failed. If this is an "
                            "authentication error, prompt the user via "
                            "`ask_question` to re-authenticate:\n\n"
                            f"```\n{details}\n```",
                        )
                        error_notified = True
                    except (subprocess.CalledProcessError, OSError) as notify_err:
                        print(
                            f"[{timestamp}] Warning: Failed to notify "
                            f"conversation: {notify_err}",
                            file=sys.stderr,
                            flush=True,
                        )
            _POLL_TRIGGER.wait(timeout=args.interval)


if __name__ == "__main__":
    main()

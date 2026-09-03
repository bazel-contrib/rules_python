#!/usr/bin/env python3
"""Continuously pulls and pushes a Git branch with fast-forward updates.

Usage:
  sync_git_branch_continuously.py [OPTIONS]

Example:
  sync_git_branch_continuously.py --pull-from-remote upstream --pull-from-branch main \
      --push-to-remote origin --push-to-branch feature --interval 30

Triggering asynchronous sync:
  kill -USR1 <PID>
"""

import argparse
import os
import shlex
import signal
import subprocess
import sys
import threading
from datetime import datetime

_SYNC_TRIGGER = threading.Event()


def handle_sync_signal(signum: int, unused_frame: object) -> None:
    """Signal handler that triggers an immediate synchronization cycle."""
    sig_name = signal.Signals(signum).name
    print(
        f"\n[Signal] Received {sig_name} ({signum}), triggering immediate sync...",
        flush=True,
    )
    _SYNC_TRIGGER.set()


def register_signal_handlers() -> None:
    """Registers signal handlers for asynchronous wakeups."""
    signal.signal(signal.SIGUSR1, handle_sync_signal)


def run_command(
    cmd: list[str],
    capture_output: bool = False,
    print_cmd: bool = True,
) -> subprocess.CompletedProcess[str]:
    """Runs a subprocess command, optionally capturing output and printing command details."""
    if print_cmd:
        print(f"+ {shlex.join(cmd)}", flush=True)
    return subprocess.run(
        cmd,
        capture_output=capture_output,
        text=True,
        check=False,
    )


def get_current_branch() -> str:
    """Returns the name of the currently checked out Git branch."""
    result = run_command(
        ["git", "branch", "--show-current"],
        capture_output=True,
        print_cmd=False,
    )
    branch = result.stdout.strip()
    if branch:
        return branch

    result = run_command(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"],
        capture_output=True,
        print_cmd=False,
    )
    return result.stdout.strip()


def get_tracking_remote(branch: str) -> str:
    """Returns the configured remote for a branch, defaulting to 'origin'."""
    result = run_command(
        ["git", "config", f"branch.{branch}.remote"],
        capture_output=True,
        print_cmd=False,
    )
    remote = result.stdout.strip()
    return remote if remote else "origin"


def sync_iteration(
    pull_remote: str,
    pull_branch: str,
    push_remote: str,
    push_branch: str,
) -> bool:
    """Performs one pull and push synchronization cycle."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(
        f"[{timestamp}] Pulling with --ff-only ({pull_remote}/{pull_branch})...",
        flush=True,
    )
    pull_cmd = ["git", "pull", "--ff-only", pull_remote, pull_branch]
    if run_command(pull_cmd).returncode != 0:
        print(
            f"[{timestamp}] Warning: git pull --ff-only failed. Will retry next"
            " interval.",
            file=sys.stderr,
            flush=True,
        )
        return False

    print(f"[{timestamp}] Pushing ({push_remote} HEAD:{push_branch})...", flush=True)
    push_cmd = ["git", "push", push_remote, f"HEAD:{push_branch}"]
    if run_command(push_cmd).returncode != 0:
        print(
            f"[{timestamp}] Warning: git push failed. Will retry next interval.",
            file=sys.stderr,
            flush=True,
        )
        return False

    print(f"[{timestamp}] Sync successful.", flush=True)
    return True


def parse_args() -> argparse.Namespace:
    """Parses command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Continuously pull and push a Git branch with fast-forward updates."
    )
    parser.add_argument(
        "--pull-from-branch",
        type=str,
        default=None,
        help="Remote branch to pull from (default: active branch)",
    )
    parser.add_argument(
        "--push-to-branch",
        type=str,
        default=None,
        help="Remote branch to push to (default: active branch)",
    )
    parser.add_argument(
        "--pull-from-remote",
        type=str,
        default=None,
        help="Remote repository to pull from (default: tracking remote or origin)",
    )
    parser.add_argument(
        "--push-to-remote",
        type=str,
        default=None,
        help="Remote repository to push to (default: tracking remote or origin)",
    )
    parser.add_argument(
        "--interval",
        type=int,
        default=60,
        help="Sleep interval in seconds between syncs (default: 60)",
    )
    return parser.parse_args()


def main() -> None:
    """Main entrypoint for the continuous sync loop."""
    args = parse_args()

    # Verify inside git repo
    check_repo = run_command(
        ["git", "rev-parse", "--is-inside-work-tree"],
        capture_output=True,
        print_cmd=False,
    )
    if check_repo.returncode != 0:
        print("Error: Not inside a Git working tree.", file=sys.stderr, flush=True)
        sys.exit(1)

    active_branch = get_current_branch()
    pull_branch = args.pull_from_branch or active_branch
    push_branch = args.push_to_branch or active_branch

    if not pull_branch or pull_branch == "HEAD":
        print(
            "Error: Could not determine pull-from-branch. Please specify"
            " --pull-from-branch.",
            file=sys.stderr,
            flush=True,
        )
        sys.exit(1)

    if not push_branch or push_branch == "HEAD":
        print(
            "Error: Could not determine push-to-branch. Please specify"
            " --push-to-branch.",
            file=sys.stderr,
            flush=True,
        )
        sys.exit(1)

    pull_remote = args.pull_from_remote or get_tracking_remote(pull_branch)
    push_remote = args.push_to_remote or get_tracking_remote(push_branch)

    register_signal_handlers()

    pid = os.getpid()
    print(
        f"Starting continuous Git sync (PID: {pid}): pull from"
        f" '{pull_remote}/{pull_branch}', push to"
        f" '{push_remote}/{push_branch}' every {args.interval}s...",
        flush=True,
    )
    print(
        f"To trigger immediate sync: kill -USR1 {pid}",
        flush=True,
    )

    while True:
        _SYNC_TRIGGER.clear()
        sync_iteration(pull_remote, pull_branch, push_remote, push_branch)
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(
            f"[{timestamp}] Sleeping for {args.interval}s (waiting for timeout or"
            f" kill -USR1 {pid})...",
            flush=True,
        )
        _SYNC_TRIGGER.wait(timeout=args.interval)


if __name__ == "__main__":
    main()

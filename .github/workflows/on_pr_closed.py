#!/usr/bin/env python3
"""Parses closed/merged PR events to dispatch release and backport workflows."""

import json
import os
import re
import subprocess
import sys


def _load_event_data() -> dict:
    """Loads event JSON payload from GITHUB_EVENT_PATH."""
    event_path = os.environ.get("GITHUB_EVENT_PATH")
    if not event_path or not os.path.isfile(event_path):
        return {}
    try:
        with open(event_path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def _write_github_output(key: str, value: str) -> None:
    """Appends key=value to $GITHUB_OUTPUT."""
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write(f"{key}={value}\n")


def _check_active_release_issue(repo: str) -> bool:
    """Checks if there is any active release tracking issue open."""
    cmd = [
        "gh",
        "issue",
        "list",
        "--label",
        "type: release",
        "--state",
        "open",
        "--json",
        "number",
    ]
    if repo:
        cmd.extend(["--repo", repo])
    res = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if res.returncode != 0:
        return False
    try:
        issues = json.loads(res.stdout or "[]")
        return bool(issues)
    except Exception:
        return False


def _check_pr_has_backport_comment(repo: str, pr_number: str) -> bool:
    """Checks if PR comments contain a /backport command."""
    cmd = ["gh", "pr", "view", pr_number, "--json", "comments"]
    if repo:
        cmd.extend(["--repo", repo])
    res = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if res.returncode != 0:
        return False
    try:
        data = json.loads(res.stdout or "{}")
        comments = data.get("comments", [])
        return any(
            re.search(r"^\s*/backport(?:\s|$)", c.get("body", ""), re.MULTILINE)
            for c in comments
        )
    except Exception:
        return False


def process_pr_closed() -> int:
    """Processes closed PR event and determines workflow to dispatch."""
    event = _load_event_data()
    pr_data = event.get("pull_request")
    if not pr_data or not isinstance(pr_data, dict):
        _write_github_output("command", "none")
        return 0

    is_merged = bool(pr_data.get("merged", False))
    pr_number = str(pr_data.get("number") or event.get("number") or "")

    if not is_merged or not pr_number:
        _write_github_output("command", "none")
        return 0

    repo = event.get("repository", {}).get("full_name") or os.environ.get(
        "GITHUB_REPOSITORY", ""
    )

    labels_data = pr_data.get("labels", [])
    labels = []
    if isinstance(labels_data, list):
        for label in labels_data:
            if isinstance(label, dict) and "name" in label:
                labels.append(label["name"])
            elif isinstance(label, str):
                labels.append(label)

    if "type: sync-changelog" in labels:
        _write_github_output("command", "complete-sync-changelog")
        _write_github_output("pr_number", pr_number)
        return 0

    if _check_active_release_issue(repo) and _check_pr_has_backport_comment(
        repo, pr_number
    ):
        _write_github_output("command", "process-backports")
        _write_github_output("pr_number", pr_number)
        return 0

    _write_github_output("command", "none")
    return 0


def _main() -> None:
    sys.exit(process_pr_closed())


if __name__ == "__main__":
    _main()

#!/usr/bin/env python3
"""Parses issue and PR comments to dispatch release and backport workflows."""

import os
import re
import subprocess
import sys


def _get_bool(key: str, default: bool = False) -> bool:
    """Returns boolean value for an environment variable."""
    val = os.environ.get(key)
    if val is None:
        return default
    return val.lower() == "true"


def _match_command(
    command: str | tuple[str, ...], comment_body: str
) -> re.Match[str] | None:
    """Matches a slash command at the start of any line, capturing optional trailing args."""
    if isinstance(command, str):
        commands = (command,)
    else:
        commands = command
    pattern = "|".join(re.escape(cmd.lstrip("/")) for cmd in commands)
    return re.search(
        rf"^\s*/(?:{pattern})(?:\s+(\S.*?))?\s*$",
        comment_body,
        re.MULTILINE,
    )


def _write_github_output(key: str, value: str) -> None:
    """Appends key=value to $GITHUB_OUTPUT."""
    path = os.environ["GITHUB_OUTPUT"]
    with open(path, "a", encoding="utf-8") as f:
        f.write(f"{key}={value}\n")


def _write_github_env(key: str, value: str) -> None:
    """Appends key=value to $GITHUB_ENV."""
    path = os.environ["GITHUB_ENV"]
    with open(path, "a", encoding="utf-8") as f:
        f.write(f"{key}={value}\n")


def _add_comment_reaction(repo: str, comment_id: str, content: str) -> None:
    """Adds a reaction to a GitHub comment using the gh CLI."""
    subprocess.run(
        [
            "gh",
            "api",
            "--method",
            "POST",
            "-H",
            "Accept: application/vnd.github+json",
            "-H",
            "X-GitHub-Api-Version: 2022-11-28",
            f"/repos/{repo}/issues/comments/{comment_id}/reactions",
            "-f",
            f"content={content}",
        ],
        check=False,
    )


def _react_negative(repo: str, comment_id: str) -> None:
    """Logs error and adds a negative reaction to the comment."""
    print("::error::No PRs specified for backport.")
    if comment_id and repo:
        _add_comment_reaction(repo=repo, comment_id=comment_id, content="-1")


def _process_release_issue_comment(
    comment_body: str,
    issue_number: str,
    repo: str = "",
    comment_id: str = "",
) -> None:
    """Processes comments on a release tracking issue."""
    if _match_command("create-rc", comment_body):
        _write_github_output("command", "create-rc")
        return

    if m := _match_command("prepare-complete", comment_body):
        _write_github_output("command", "prepare-complete")
        if pr_arg := re.sub(r"[\s#]", "", m.group(1)) if m.group(1) else "":
            _write_github_output("pr_number", pr_arg)
        return

    if _match_command("create-release-branch", comment_body):
        _write_github_output("command", "create-release-branch")
        return

    if _match_command("prepare", comment_body):
        _write_github_output("command", "prepare")
        return

    if _match_command("process-backports", comment_body):
        _write_github_output("command", "process-backports")
        return

    if _match_command("sync-changelog", comment_body):
        _write_github_output("command", "sync-changelog")
        return

    if m := _match_command(("backport", "backports"), comment_body):
        raw_args = m.group(1) if m.group(1) else ""
        items = [item for item in re.split(r"[\s,]+", raw_args) if item]
        if csv := ",".join(items):
            _write_github_output("command", "add-backports")
            _write_github_output("backports", csv)
        else:
            _write_github_output("command", "none")
            _react_negative(repo=repo, comment_id=comment_id)
        return

    if _match_command("promote", comment_body):
        _write_github_output("command", "promote")
        return

    _write_github_output("command", "none")


def _process_backport_issue_comment(comment_body: str) -> None:
    """Processes comments on a backport tracking issue."""
    if _match_command("prepare", comment_body):
        _write_github_output("command", "backport-prepare")
        return

    if _match_command("create-releases", comment_body):
        _write_github_output("command", "backport-create-releases")
        return

    _write_github_output("command", "none")


def _process_pr_comment(comment_body: str, pr_number: str) -> None:
    """Processes comments on a pull request."""
    if _match_command(("backport", "backports"), comment_body):
        _write_github_output("command", "pr-backport")
        _write_github_output("pr_number", pr_number)
        return

    if _match_command("prepare-complete", comment_body):
        _write_github_output("command", "prepare-complete")
        _write_github_output("pr_number", pr_number)
        return

    _write_github_output("command", "none")


def process_comment() -> int:
    """Processes a comment from environment variables and dispatches actions."""
    comment_body = os.environ.get("COMMENT_BODY", "")
    is_pr = _get_bool("IS_PR")
    event_number = os.environ.get("EVENT_NUMBER", "")
    has_release_label = _get_bool("HAS_RELEASE_LABEL")
    has_backport_label = _get_bool("HAS_BACKPORT_LABEL")
    comment_id = os.environ.get("COMMENT_ID", "")
    repo = os.environ.get("GITHUB_REPOSITORY", "")

    if is_pr:
        _process_pr_comment(
            comment_body=comment_body,
            pr_number=event_number,
        )
        return 0

    issue_number = event_number
    _write_github_output("issue_number", issue_number)
    _write_github_env("issue_number", issue_number)

    if has_release_label:
        _process_release_issue_comment(
            comment_body=comment_body,
            issue_number=issue_number,
            repo=repo,
            comment_id=comment_id,
        )
    elif has_backport_label:
        _process_backport_issue_comment(
            comment_body=comment_body,
        )
    else:
        _write_github_output("command", "none")

    return 0


def _main() -> None:
    sys.exit(process_comment())


if __name__ == "__main__":
    _main()

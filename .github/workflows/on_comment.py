#!/usr/bin/env python3
"""Parses issue and PR comments to dispatch release and backport workflows."""

import argparse
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


def _post_issue_comment(repo: str, issue_number: str, body: str) -> None:
    """Posts a comment to a GitHub issue or PR using the gh CLI."""
    subprocess.run(
        [
            "gh",
            "issue",
            "comment",
            issue_number,
            f"--repo={repo}",
            f"--body={body}",
        ],
        check=True,
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


def _report_failure() -> int:
    """Posts a failure comment and negative reaction when a workflow fails."""
    event = _load_event_data()
    issue_data = event.get("issue") or {}
    comment_data = event.get("comment") or {}
    repo_data = event.get("repository") or {}

    event_number = str(issue_data.get("number") or os.environ.get("EVENT_NUMBER", ""))
    comment_id = str(comment_data.get("id") or os.environ.get("COMMENT_ID", ""))
    comment_url = str(comment_data.get("html_url") or os.environ.get("COMMENT_URL", ""))
    repo = str(repo_data.get("full_name") or os.environ.get("GITHUB_REPOSITORY", ""))
    command = os.environ.get("COMMAND", "")
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    server_url = os.environ.get("GITHUB_SERVER_URL", "https://github.com")

    if comment_id and repo:
        _add_comment_reaction(repo=repo, comment_id=comment_id, content="-1")

    if not event_number or not repo:
        print(
            "::error::Issue number and repository are required to post a"
            " failure comment."
        )
        return 1

    if command and command != "none":
        if comment_url:
            header = (
                f"Workflow failed for command `{command}` ([comment]({comment_url}))."
            )
        else:
            header = f"Workflow failed for command `{command}`."
    else:
        if comment_url:
            header = f"Workflow failed while processing [comment]({comment_url})."
        else:
            header = "Workflow failed while processing comment."

    if run_id:
        run_url = f"{server_url}/{repo}/actions/runs/{run_id}"
        details = f"See [workflow run]({run_url}) for logs."
    else:
        details = "See workflow logs for details."

    body = f"{header}\n\n{details}"
    _post_issue_comment(repo=repo, issue_number=event_number, body=body)
    return 0


def process_comment(*, report_failure: bool = False) -> int:
    """Processes a comment from environment variables and dispatches actions."""
    if report_failure:
        return _report_failure()

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


def _main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--report-failure",
        action="store_true",
        help="Post a failure comment to the issue or PR.",
    )
    args = parser.parse_args(argv if argv is not None else [])
    sys.exit(process_comment(report_failure=args.report_failure))


if __name__ == "__main__":
    _main(sys.argv[1:])

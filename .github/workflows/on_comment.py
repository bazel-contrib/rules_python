#!/usr/bin/env python3
"""Parses issue and PR comments to dispatch release and backport workflows."""

import argparse
import enum
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


class _Command(enum.StrEnum):
    """Workflow commands dispatched from issue and PR comments."""

    NONE = "none"
    CREATE_RC = "create-rc"
    PREPARE_COMPLETE = "prepare-complete"
    CREATE_RELEASE_BRANCH = "create-release-branch"
    PREPARE = "prepare"
    PROCESS_BACKPORTS = "process-backports"
    SYNC_CHANGELOG = "sync-changelog"
    ADD_BACKPORTS = "add-backports"
    PROMOTE = "promote"
    BACKPORT_PREPARE = "backport-prepare"
    BACKPORT_CREATE_RELEASES = "backport-create-releases"
    PR_BACKPORT = "pr-backport"


_ALLOWED_AUTHOR_ASSOCIATIONS = frozenset({"OWNER", "MEMBER", "COLLABORATOR"})
_BACKPORT_ALLOWED_USERS: frozenset[str] = frozenset(
    [
        "gholms",
    ]
)


def _is_command_allowed(
    command: _Command,
    *,
    user_login: str,
    author_association: str,
) -> bool:
    """Returns whether the user is allowed to trigger the given command."""
    if command in (_Command.ADD_BACKPORTS, _Command.PR_BACKPORT) and (
        user_login in _BACKPORT_ALLOWED_USERS
    ):
        return True
    if author_association in _ALLOWED_AUTHOR_ASSOCIATIONS:
        return True
    return False


def _process_release_issue_comment(
    comment_body: str,
    issue_number: str,
    repo: str = "",
    comment_id: str = "",
) -> _Command:
    """Processes comments on a release tracking issue."""
    if _match_command("create-rc", comment_body):
        _write_github_output("command", _Command.CREATE_RC)
        return _Command.CREATE_RC

    if m := _match_command("prepare-complete", comment_body):
        _write_github_output("command", _Command.PREPARE_COMPLETE)
        if pr_arg := re.sub(r"[\s#]", "", m.group(1)) if m.group(1) else "":
            _write_github_output("pr_number", pr_arg)
        return _Command.PREPARE_COMPLETE

    if _match_command("create-release-branch", comment_body):
        _write_github_output("command", _Command.CREATE_RELEASE_BRANCH)
        return _Command.CREATE_RELEASE_BRANCH

    if _match_command("prepare", comment_body):
        _write_github_output("command", _Command.PREPARE)
        return _Command.PREPARE

    if _match_command("process-backports", comment_body):
        _write_github_output("command", _Command.PROCESS_BACKPORTS)
        return _Command.PROCESS_BACKPORTS

    if _match_command("sync-changelog", comment_body):
        _write_github_output("command", _Command.SYNC_CHANGELOG)
        return _Command.SYNC_CHANGELOG

    if m := _match_command(("backport", "backports"), comment_body):
        raw_args = m.group(1) if m.group(1) else ""
        items = [item for item in re.split(r"[\s,]+", raw_args) if item]
        if csv := ",".join(items):
            _write_github_output("command", _Command.ADD_BACKPORTS)
            _write_github_output("backports", csv)
            return _Command.ADD_BACKPORTS
        else:
            _write_github_output("command", _Command.NONE)
            _react_negative(repo=repo, comment_id=comment_id)
            return _Command.NONE

    if _match_command("promote", comment_body):
        _write_github_output("command", _Command.PROMOTE)
        return _Command.PROMOTE

    _write_github_output("command", _Command.NONE)
    return _Command.NONE


def _process_backport_issue_comment(comment_body: str) -> _Command:
    """Processes comments on a backport tracking issue."""
    if _match_command("prepare", comment_body):
        _write_github_output("command", _Command.BACKPORT_PREPARE)
        return _Command.BACKPORT_PREPARE

    if _match_command("create-releases", comment_body):
        _write_github_output("command", _Command.BACKPORT_CREATE_RELEASES)
        return _Command.BACKPORT_CREATE_RELEASES

    _write_github_output("command", _Command.NONE)
    return _Command.NONE


def _process_pr_comment(comment_body: str, pr_number: str) -> _Command:
    """Processes comments on a pull request."""
    if _match_command(("backport", "backports"), comment_body):
        _write_github_output("command", _Command.PR_BACKPORT)
        _write_github_output("pr_number", pr_number)
        return _Command.PR_BACKPORT

    if _match_command("prepare-complete", comment_body):
        _write_github_output("command", _Command.PREPARE_COMPLETE)
        _write_github_output("pr_number", pr_number)
        return _Command.PREPARE_COMPLETE

    _write_github_output("command", _Command.NONE)
    return _Command.NONE


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

    if command and command != _Command.NONE:
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

    event = _load_event_data()
    comment_data = event.get("comment") or {}
    author_association = str(comment_data.get("author_association") or "")
    user_data = comment_data.get("user") or {}
    user_login = str(user_data.get("login") or "")

    comment_body = os.environ.get("COMMENT_BODY", "")
    is_pr = _get_bool("IS_PR")
    event_number = os.environ.get("EVENT_NUMBER", "")
    has_release_label = _get_bool("HAS_RELEASE_LABEL")
    has_backport_label = _get_bool("HAS_BACKPORT_LABEL")
    comment_id = os.environ.get("COMMENT_ID", "")
    repo = os.environ.get("GITHUB_REPOSITORY", "")

    if is_pr:
        command = _process_pr_comment(
            comment_body=comment_body,
            pr_number=event_number,
        )
    else:
        issue_number = event_number
        _write_github_output("issue_number", issue_number)
        _write_github_env("issue_number", issue_number)

        if has_release_label:
            command = _process_release_issue_comment(
                comment_body=comment_body,
                issue_number=issue_number,
                repo=repo,
                comment_id=comment_id,
            )
        elif has_backport_label:
            command = _process_backport_issue_comment(
                comment_body=comment_body,
            )
        else:
            _write_github_output("command", _Command.NONE)
            command = _Command.NONE

    if command != _Command.NONE and not _is_command_allowed(
        command,
        user_login=user_login,
        author_association=author_association,
    ):
        print(
            f"::error::User '{user_login}' (association: '{author_association}')"
            f" is not allowed to trigger command '{command}'."
        )
        return 1

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

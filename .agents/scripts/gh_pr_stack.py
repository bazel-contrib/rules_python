#!/usr/bin/env python3
"""Manage native GitHub pull request stacks via the GitHub REST API.

Usage:
  .agents/scripts/gh_pr_stack.py create <pr1> <pr2> [<prN>...] [--repo <owner/name>]
  .agents/scripts/gh_pr_stack.py add <stack_number> <pr1> [<prN>...] [--repo <owner/name>]
  .agents/scripts/gh_pr_stack.py unstack <stack_number> <pr1> [<prN>...] [--repo <owner/name>]
  .agents/scripts/gh_pr_stack.py show <stack_number> [--repo <owner/name>]
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from collections.abc import Sequence

_DEFAULT_REPO = "bazel-contrib/rules_python"
_ACCEPT_HEADER = "Accept: application/vnd.github+json"
_REPO_SLUG_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\Z")


def build_parser() -> argparse.ArgumentParser:
    """Builds the CLI argument parser.

    Returns:
        Configured `argparse.ArgumentParser` for `gh_pr_stack`.
    """
    parser = argparse.ArgumentParser(
        description="Manage native GitHub pull request stacks."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    create_parser = subparsers.add_parser(
        "create", help="Create a new stack with two or more PR numbers"
    )
    create_parser.add_argument(
        "prs", type=int, nargs="+", help="PR numbers to include in the stack"
    )
    create_parser.add_argument("--repo", default=_DEFAULT_REPO, help="Owner/repo slug")

    add_parser = subparsers.add_parser(
        "add", help="Add one or more PR numbers to an existing stack"
    )
    add_parser.add_argument("stack_number", type=int, help="Stack number")
    add_parser.add_argument("prs", type=int, nargs="+", help="PR numbers to add")
    add_parser.add_argument("--repo", default=_DEFAULT_REPO, help="Owner/repo slug")

    unstack_parser = subparsers.add_parser(
        "unstack", help="Remove one or more PR numbers from an existing stack"
    )
    unstack_parser.add_argument("stack_number", type=int, help="Stack number")
    unstack_parser.add_argument("prs", type=int, nargs="+", help="PR numbers to remove")
    unstack_parser.add_argument("--repo", default=_DEFAULT_REPO, help="Owner/repo slug")

    show_parser = subparsers.add_parser("show", help="Display an existing stack")
    show_parser.add_argument("stack_number", type=int, help="Stack number")
    show_parser.add_argument("--repo", default=_DEFAULT_REPO, help="Owner/repo slug")

    return parser


def validate_repo_slug(repo: str) -> str:
    """Validates an `owner/name` repository slug fail-closed.

    Args:
        repo: Repository slug in `owner/name` format.

    Returns:
        The validated `owner/name` slug.
    """
    if not _REPO_SLUG_RE.match(repo):
        raise ValueError(f"Invalid repository slug: {repo!r}")
    owner, name = repo.split("/", 1)
    if (
        owner in {".", ".."}
        or name in {".", ".."}
        or owner.startswith("-")
        or name.startswith("-")
    ):
        raise ValueError(f"Invalid repository slug: {repo!r}")
    return repo


def run_gh_api(args: Sequence[str]) -> dict:
    """Runs `gh api` with the given arguments and parses the JSON response.

    Args:
        args: Arguments forwarded to `gh api` after the `Accept` header.

    Returns:
        Parsed JSON object returned by the GitHub REST API.
    """
    result = subprocess.run(
        ["gh", "api", "-H", _ACCEPT_HEADER, *args],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout or "{}")


def create_stack(repo: str, pull_requests: Sequence[int]) -> dict:
    """Creates a new GitHub PR stack containing `pull_requests`.

    Args:
        repo: Repository slug in `owner/name` format.
        pull_requests: Pull request numbers (at least two) in stack order.

    Returns:
        Created stack metadata dict from GitHub REST API.
    """
    if len(pull_requests) < 2:
        raise ValueError("Creating a stack requires at least 2 pull request numbers")
    slug = validate_repo_slug(repo)
    fields = [f"-F=pull_requests[]={pr}" for pr in pull_requests]
    return run_gh_api(["-X", "POST", f"repos/{slug}/stacks", *fields])


def add_to_stack(repo: str, stack_number: int, pull_requests: Sequence[int]) -> dict:
    """Adds `pull_requests` to an existing GitHub PR stack.

    Args:
        repo: Repository slug in `owner/name` format.
        stack_number: Existing GitHub stack number.
        pull_requests: Pull request numbers to append to the stack.

    Returns:
        Updated stack metadata dict from GitHub REST API.
    """
    slug = validate_repo_slug(repo)
    fields = [f"-F=pull_requests[]={pr}" for pr in pull_requests]
    return run_gh_api(
        ["-X", "POST", f"repos/{slug}/stacks/{stack_number}/add", *fields]
    )


def unstack_prs(repo: str, stack_number: int, pull_requests: Sequence[int]) -> dict:
    """Removes `pull_requests` from an existing GitHub PR stack.

    Args:
        repo: Repository slug in `owner/name` format.
        stack_number: Existing GitHub stack number.
        pull_requests: Pull request numbers to remove from the stack.

    Returns:
        Updated stack metadata dict from GitHub REST API.
    """
    slug = validate_repo_slug(repo)
    fields = [f"-F=pull_requests[]={pr}" for pr in pull_requests]
    return run_gh_api(
        ["-X", "POST", f"repos/{slug}/stacks/{stack_number}/unstack", *fields]
    )


def show_stack(repo: str, stack_number: int) -> dict:
    """Fetches metadata and pull request membership for a GitHub PR stack.

    Args:
        repo: Repository slug in `owner/name` format.
        stack_number: Existing GitHub stack number.

    Returns:
        Stack metadata dict from GitHub REST API.
    """
    slug = validate_repo_slug(repo)
    return run_gh_api([f"repos/{slug}/stacks/{stack_number}"])


def format_stack(data: dict) -> str:
    """Formats stack JSON data as a human-readable summary.

    Args:
        data: Stack metadata dict returned by the GitHub `/stacks` API.

    Returns:
        Multi-line summary string listing the stack header and each PR.
    """
    lines = [f"stack #{data['number']} base={data['base']['ref']} open={data['open']}"]
    for pr in data.get("pull_requests", []):
        lines.append(
            f"  #{pr['number']} {pr['head']['ref']} -> {pr['base']['ref']} "
            f"draft={pr['draft']} state={pr['state']}"
        )
    return "\n".join(lines)


def main(argv: Sequence[str] | None = None) -> int:
    """CLI entrypoint.

    Args:
        argv: Command-line arguments (excluding `sys.argv[0]`), or `None` to use
            `sys.argv[1:]`.

    Returns:
        Process exit code (`0` on success).
    """
    args = build_parser().parse_args(argv)
    if args.command == "create":
        data = create_stack(args.repo, args.prs)
    elif args.command == "add":
        data = add_to_stack(args.repo, args.stack_number, args.prs)
    elif args.command == "unstack":
        data = unstack_prs(args.repo, args.stack_number, args.prs)
    elif args.command == "show":
        data = show_stack(args.repo, args.stack_number)
    else:
        raise ValueError(f"Unsupported command: {args.command!r}")
    print(format_stack(data))
    return 0


if __name__ == "__main__":
    sys.exit(main())

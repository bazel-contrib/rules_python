#!/usr/bin/env python3
"""Configures git tracking and user environment for rules_python worktrees."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def _get_current_branch() -> str:
    result = subprocess.run(
        ["git", "symbolic-ref", "--short", "HEAD"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return ""
    return result.stdout.strip()


def _get_workspace_root() -> Path:
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        check=True,
    )
    return Path(result.stdout.strip())


def setup_triangle_branch(branch: str) -> None:
    """Configures local git tracking to pull from upstream and push to origin."""
    print(f"Setting up upstream tracking for branch: {branch}")
    subprocess.check_call(
        ["git", "config", "--local", f"branch.{branch}.remote", "upstream"]
    )
    subprocess.check_call(
        ["git", "config", "--local", f"branch.{branch}.merge", "refs/heads/main"]
    )
    subprocess.check_call(
        ["git", "config", "--local", f"branch.{branch}.pushRemote", "origin"]
    )
    subprocess.check_call(["git", "config", "--local", "push.default", "current"])
    print(
        "Successfully configured upstream/main tracking and origin pushRemote "
        f"for {branch}!"
    )


def setup_buildbuddy_user_bazelrc(workspace_root: Path) -> None:
    """Links user BuildBuddy config to workspace user.bazelrc if not present."""
    source_rc = (
        Path.home() / ".config" / "rules_python" / "buildbuddy.bazelrc"
    ).resolve()
    target_rc = workspace_root / "user.bazelrc"

    if not source_rc.exists():
        print(
            f"Note: {source_rc} not found. Skipping user.bazelrc link "
            "(BuildBuddy RBE may not work for local invocations)."
        )
        return

    # Only create the symlink if user.bazelrc does not already exist
    if target_rc.exists() or target_rc.is_symlink():
        print(f"user.bazelrc already exists at {target_rc}. Skipping link.")
        return

    target_rc.symlink_to(source_rc)
    print(f"Linked {source_rc} -> {target_rc}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Setup git tracking and environment for rules_python workspace."
    )
    parser.add_argument(
        "branch",
        nargs="?",
        default=None,
        help="Branch name to configure (defaults to current branch)",
    )
    args = parser.parse_args()

    branch = args.branch or _get_current_branch()
    if not branch:
        print(
            "Error: Could not detect current branch name and none was provided.",
            file=sys.stderr,
        )
        return 1

    workspace_root = _get_workspace_root()
    setup_triangle_branch(branch)
    setup_buildbuddy_user_bazelrc(workspace_root)
    return 0


if __name__ == "__main__":
    sys.exit(main())

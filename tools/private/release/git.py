"""Git helper functions for the release tool."""

import subprocess

from tools.private.release.utils import run_cmd


def get_tags():
    """Returns a list of all git tags in the repository."""
    output = run_cmd("git", "tag")
    return output.splitlines() if output else []


def checkout(ref, create_branch=False):
    """Checks out a git reference (tag, branch, or commit)."""
    if create_branch:
        run_cmd("git", "checkout", "-b", ref, capture_output=False)
    else:
        run_cmd("git", "checkout", ref, capture_output=False)


def add(*files):
    """Stages files for commit."""
    run_cmd("git", "add", *files, capture_output=False)


def commit(message, amend=False, no_edit=False):
    """Commits staged changes, optionally amending the previous commit."""
    cmd = ["git", "commit"]
    if amend:
        cmd.append("--amend")
    if no_edit:
        cmd.append("--no-edit")
    if message:
        cmd.extend(["-m", message])
    run_cmd(*cmd, capture_output=False)


def push(remote, ref):
    """Pushes a reference to a remote repository."""
    run_cmd("git", "push", remote, ref, capture_output=False)


def fetch(remote="origin", tags=False, force=False):
    """Fetches updates from a remote repository."""
    cmd = ["git", "fetch", remote]
    if tags:
        cmd.append("--tags")
    if force:
        cmd.append("--force")
    run_cmd(*cmd, capture_output=False)


def merge(commit_ref, ff_only=True):
    """Merges a commit into the current branch."""
    cmd = ["git", "merge", commit_ref]
    if ff_only:
        cmd.append("--ff-only")
    run_cmd(*cmd, capture_output=False)


def tag(tag_name):
    """Creates a local tag pointing to HEAD."""
    run_cmd("git", "tag", tag_name, capture_output=False)


def cherry_pick(sha):
    """Cherry-picks a commit using -x to append the original commit info."""
    run_cmd("git", "cherry-pick", "-x", sha, capture_output=False)


def cherry_pick_abort():
    """Aborts an in-progress cherry-pick operation."""
    run_cmd("git", "cherry-pick", "--abort", capture_output=False)


def status():
    """Returns the output of git status --porcelain."""
    return run_cmd("git", "status", "--porcelain")


def get_commit_sha(ref="HEAD", short=False):
    """Returns the commit SHA of a given reference."""
    cmd = ["git", "rev-parse"]
    if short:
        cmd.append("--short")
    cmd.append(ref)
    return run_cmd(*cmd)


def branch_exists(branch_name):
    """Returns True if a local branch exists."""
    try:
        run_cmd("git", "show-ref", "--verify", f"refs/heads/{branch_name}")
        return True
    except subprocess.CalledProcessError:
        return False


def tag_exists(tag_name):
    """Returns True if a local tag exists."""
    try:
        run_cmd("git", "show-ref", "--verify", f"refs/tags/{tag_name}")
        return True
    except subprocess.CalledProcessError:
        return False


def sort_commits_chronologically(shas):
    """Sorts a list of commit SHAs chronologically (oldest first)."""
    output = run_cmd("git", "log", "--no-walk", "--reverse", "--format=%H", *shas)
    return output.splitlines() if output else []


def get_tags_at_head():
    """Returns a list of tags pointing at the current HEAD commit."""
    output = run_cmd("git", "tag", "--points-at", "HEAD")
    return output.splitlines() if output else []


def get_current_branch():
    """Returns the current git branch name, or None if not in a git repo."""
    try:
        return run_cmd("git", "rev-parse", "--abbrev-ref", "HEAD")
    except subprocess.CalledProcessError:
        return None

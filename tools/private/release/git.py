"""Git helper functions for the release tool."""

import subprocess

from tools.private.release.shell import run_cmd


def get_tags():
    """Returns a list of all git tags in the repository."""
    output = run_cmd("git", "tag")
    return output.splitlines() if output else []


def checkout(
    ref: str, create_branch: bool = False, track_remote: str | None = None
) -> None:
    """Checks out a git reference (tag, branch, or commit).

    Args:
        ref: The git reference (tag, branch, or commit) to checkout.
        create_branch: If True, creates the branch before checking it out.
        track_remote: If specified, checks out the branch tracking this remote's
            corresponding branch.
    """
    cmd = ["git", "checkout"]
    if create_branch:
        cmd.append("-b")

    should_reset_hard = False
    if track_remote:
        if branch_exists(ref):
            cmd.append(ref)
            should_reset_hard = True
        else:
            cmd.extend(["--track", f"{track_remote}/{ref}"])
    else:
        cmd.append(ref)
    run_cmd(*cmd, capture_output=False)

    if should_reset_hard:
        reset_hard(f"{track_remote}/{ref}")


def add(*files):
    """Stages files for commit."""
    run_cmd("git", "add", *files, capture_output=False)


def add_modified_and_deleted():
    """Stages all modified and deleted tracked files."""
    run_cmd("git", "add", "--update", capture_output=False)


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


def push(remote, ref, set_upstream=False, force=False):
    """Pushes a reference to a remote repository."""
    cmd = ["git", "push"]
    if set_upstream:
        cmd.append("--set-upstream")
    if force:
        cmd.append("--force")
    cmd.extend([remote, ref])
    run_cmd(*cmd, capture_output=False)


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


def tag(tag_name, commit_ref):
    """Creates a local tag pointing to a specific commit."""
    run_cmd("git", "tag", tag_name, commit_ref, capture_output=False)


def cherry_pick(sha: str) -> None:
    """Cherry-picks a commit.

    Args:
        sha: The commit SHA to cherry-pick.
    """
    run_cmd("git", "cherry-pick", "-x", sha, capture_output=False)


def cherry_pick_abort():
    """Aborts an in-progress cherry-pick operation."""
    run_cmd("git", "cherry-pick", "--abort", capture_output=False)


def reset_hard(ref: str = "HEAD") -> None:
    """Resets the index and working tree to a specific reference.

    Args:
        ref: The git reference to reset to. Defaults to 'HEAD'.
    """
    run_cmd("git", "reset", "--hard", ref, capture_output=False)


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


def get_commit_message(ref: str = "HEAD") -> str:
    """Returns the commit message of a given reference.

    Args:
        ref: The git reference to get the message from. Defaults to 'HEAD'.
    """
    return run_cmd("git", "log", "-1", "--format=%B", ref)


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


def get_current_branch():
    """Returns the current git branch name."""
    return run_cmd("git", "rev-parse", "--abbrev-ref", "HEAD")


def remote_branch_exists(remote, branch_name):
    """Returns True if a remote branch exists."""
    try:
        run_cmd("git", "show-ref", "--verify", f"refs/remotes/{remote}/{branch_name}")
        return True
    except subprocess.CalledProcessError:
        return False


def is_ancestor(ancestor, descendant):
    """Returns True if ancestor is an ancestor of descendant (fast-forwardable)."""
    try:
        run_cmd("git", "merge-base", "--is-ancestor", ancestor, descendant)
        return True
    except subprocess.CalledProcessError:
        return False


def get_remote_tags(remote: str) -> list[str]:
    """Returns a list of tags present on the specified remote repository.

    Args:
        remote: The name of the git remote to query (e.g., 'origin', 'upstream').

    Returns:
        A list of tag names (strings) found on the remote, excluding peeled tags.
    """
    output = run_cmd("git", "ls-remote", "--tags", remote)
    tags = []
    for line in output.splitlines():
        if not line:
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        ref = parts[1]
        if ref.startswith("refs/tags/"):
            tag = ref[len("refs/tags/") :]
            # Skip peeled tags (e.g. tag^{}) to avoid
            # duplicate tag names in the output.
            if not tag.endswith("^{}"):
                tags.append(tag)
    return tags

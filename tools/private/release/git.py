"""Git helper functions for the release tool."""

import subprocess

from tools.private.release.shell import run_cmd


class Git:
    """Git helper class for the release tool.

    Operates on a specific git repository path.
    """

    def __init__(self, repo: str):
        """Initializes the Git helper.

        Args:
            repo: The path to the git repository.
        """
        self._repo = repo

    def _run_git(
        self, *args: str, check: bool = True, capture_output: bool = True
    ) -> str | None:
        """Runs a git command in the repository directory.

        Args:
            *args: Arguments passed to the git command.
            check: If True, raises CalledProcessError on failure.
            capture_output: If True, captures and returns stdout.

        Returns:
            The stdout of the command, stripped, or None if capture_output is
            False.
        """
        return run_cmd(
            "git",
            *args,
            check=check,
            capture_output=capture_output,
            cwd=self._repo,
        )

    def get_tags(self) -> list[str]:
        """Returns a list of all git tags in the repository.

        Returns:
            A list of tag names (strings).
        """
        output = self._run_git("tag")
        return output.splitlines() if output else []

    def checkout(
        self,
        ref: str,
        create_branch: bool = False,
        track_remote: str | None = None,
    ) -> None:
        """Checks out a git reference (tag, branch, or commit).

        Args:
            ref: The git reference (tag, branch, or commit) to checkout.
            create_branch: If True, creates the branch before checking it out.
            track_remote: If specified, checks out the branch tracking this
              remote's corresponding branch.
        """
        cmd = ["checkout"]
        if create_branch:
            cmd.append("-b")

        should_reset_hard = False
        if track_remote:
            if self.branch_exists(ref):
                cmd.append(ref)
                should_reset_hard = True
            else:
                cmd.extend(["--track", f"{track_remote}/{ref}"])
        else:
            cmd.append(ref)
        self._run_git(*cmd, capture_output=False)

        if should_reset_hard:
            self.reset_hard(f"{track_remote}/{ref}")

    def add(self, *files: str) -> None:
        """Stages files for commit.

        Args:
            *files: Paths to files to stage.
        """
        self._run_git("add", *files, capture_output=False)

    def add_modified_and_deleted(self) -> None:
        """Stages all modified and deleted tracked files."""
        self._run_git("add", "--update", capture_output=False)

    def commit(self, message: str, amend: bool = False, no_edit: bool = False) -> None:
        """Commits staged changes, optionally amending the previous commit.

        Args:
            message: The commit message.
            amend: If True, amends the previous commit.
            no_edit: If True, uses the existing commit message without editing.
        """
        cmd = ["commit"]
        if amend:
            cmd.append("--amend")
        if no_edit:
            cmd.append("--no-edit")
        if message:
            cmd.extend(["-m", message])
        self._run_git(*cmd, capture_output=False)

    def push(
        self,
        remote: str,
        ref: str,
        set_upstream: bool = False,
        force: bool = False,
    ) -> None:
        """Pushes a reference to a remote repository.

        Args:
            remote: The remote repository name (e.g., 'origin').
            ref: The reference to push (e.g., a branch name).
            set_upstream: If True, sets the upstream tracking branch.
            force: If True, force pushes the changes.
        """
        cmd = ["push"]
        if set_upstream:
            cmd.append("--set-upstream")
        if force:
            cmd.append("--force")
        cmd.extend([remote, ref])
        self._run_git(*cmd, capture_output=False)

    def fetch(
        self,
        remote: str = "origin",
        refspec: str | None = None,
        tags: bool = False,
        force: bool = False,
    ) -> None:
        """Fetches updates from a remote repository.

        Args:
            remote: The remote repository name. Defaults to 'origin'.
            refspec: The refspec to fetch.
            tags: If True, fetches all tags.
            force: If True, force fetches updates.
        """
        cmd = ["fetch", remote]
        if refspec:
            cmd.append(refspec)
        if tags:
            cmd.append("--tags")
        if force:
            cmd.append("--force")
        self._run_git(*cmd, capture_output=False)

    def merge(self, commit_ref: str, ff_only: bool = True) -> None:
        """Merges a commit into the current branch.

        Args:
            commit_ref: The commit reference to merge.
            ff_only: If True, only allows fast-forward merges.
        """
        cmd = ["merge", commit_ref]
        if ff_only:
            cmd.append("--ff-only")
        self._run_git(*cmd, capture_output=False)

    def tag(self, tag_name: str, commit_ref: str) -> None:
        """Creates a local tag pointing to a specific commit.

        Args:
            tag_name: The name of the tag to create.
            commit_ref: The commit reference the tag should point to.
        """
        self._run_git("tag", tag_name, commit_ref, capture_output=False)

    def cherry_pick(self, sha: str) -> None:
        """Cherry-picks a commit.

        Args:
            sha: The commit SHA to cherry-pick.
        """
        self._run_git("cherry-pick", "-x", sha, capture_output=False)

    def cherry_pick_abort(self) -> None:
        """Aborts an in-progress cherry-pick operation."""
        self._run_git("cherry-pick", "--abort", capture_output=False)

    def reset_hard(self, ref: str = "HEAD") -> None:
        """Resets the index and working tree to a specific reference.

        Args:
            ref: The git reference to reset to. Defaults to 'HEAD'.
        """
        self._run_git("reset", "--hard", ref, capture_output=False)

    def status(self) -> str:
        """Returns the output of git status --porcelain.

        Returns:
            The porcelain status output.
        """
        output = self._run_git("status", "--porcelain")
        return output if output else ""

    def get_commit_sha(self, ref: str = "HEAD", short: bool = False) -> str:
        """Returns the commit SHA of a given reference.

        Args:
            ref: The git reference. Defaults to 'HEAD'.
            short: If True, returns a short SHA.

        Returns:
            The commit SHA.
        """
        cmd = ["rev-parse"]
        if short:
            cmd.append("--short")
        cmd.append(ref)
        output = self._run_git(*cmd)
        return output if output else ""

    def get_commit_message(self, ref: str = "HEAD") -> str:
        """Returns the commit message of a given reference.

        Args:
            ref: The git reference. Defaults to 'HEAD'.

        Returns:
            The commit message.
        """
        output = self._run_git("log", "-1", "--format=%B", ref)
        return output if output else ""

    def branch_exists(self, branch_name: str) -> bool:
        """Returns True if a local branch exists.

        Args:
            branch_name: The name of the branch to check.

        Returns:
            True if the branch exists, False otherwise.
        """
        try:
            self._run_git("show-ref", "--verify", f"refs/heads/{branch_name}")
            return True
        except subprocess.CalledProcessError:
            return False

    def tag_exists(self, tag_name: str) -> bool:
        """Returns True if a local tag exists.

        Args:
            tag_name: The name of the tag to check.

        Returns:
            True if the tag exists, False otherwise.
        """
        try:
            self._run_git("show-ref", "--verify", f"refs/tags/{tag_name}")
            return True
        except subprocess.CalledProcessError:
            return False

    def sort_commits_chronologically(self, shas: list[str]) -> list[str]:
        """Sorts a list of commit SHAs chronologically (oldest first).

        Args:
            shas: A list of commit SHAs to sort.

        Returns:
            The sorted list of commit SHAs.
        """
        output = self._run_git("log", "--no-walk", "--reverse", "--format=%H", *shas)
        return output.splitlines() if output else []

    def get_current_branch(self) -> str:
        """Returns the current git branch name.

        Returns:
            The current branch name.
        """
        output = self._run_git("rev-parse", "--abbrev-ref", "HEAD")
        return output if output else ""

    def remote_branch_exists(self, remote: str, branch_name: str) -> bool:
        """Returns True if a remote branch exists.

        Args:
            remote: The name of the remote.
            branch_name: The name of the branch.

        Returns:
            True if the remote branch exists, False otherwise.
        """
        try:
            self._run_git(
                "show-ref",
                "--verify",
                f"refs/remotes/{remote}/{branch_name}",
            )
            return True
        except subprocess.CalledProcessError:
            return False

    def is_ancestor(self, ancestor: str, descendant: str) -> bool:
        """Returns True if ancestor is an ancestor of descendant.

        Args:
            ancestor: The commit reference that might be an ancestor.
            descendant: The commit reference that might be a descendant.

        Returns:
            True if ancestor is an ancestor of descendant, False otherwise.
        """
        try:
            self._run_git("merge-base", "--is-ancestor", ancestor, descendant)
            return True
        except subprocess.CalledProcessError:
            return False

    def get_remote_tags(self, remote: str) -> list[str]:
        """Returns a list of tags present on the specified remote repository.

        Args:
            remote: The name of the git remote to query (e.g., 'origin',
              'upstream').

        Returns:
            A list of tag names (strings) found on the remote, excluding peeled
            tags.
        """
        output = self._run_git("ls-remote", "--tags", remote)
        tags = []
        if not output:
            return tags
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

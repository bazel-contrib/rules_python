"""GitHub CLI helper functions for the release tool."""

import enum
import json
import os
import re
import tempfile
from typing import TypedDict

from tools.private.release.release_issue import BackportTask
from tools.private.release.shell import run_cmd

# GitHub label types
RELEASE_LABEL = "type: release"
BACKPORT_LABEL = "type: backport-pr"

# GitHub reaction types
# See: https://docs.github.com/en/rest/reactions/reactions?apiVersion=2022-11-28#about-reactions
GH_REACTION_THUMBS_UP = "+1"
GH_REACTION_THUMBS_DOWN = "-1"
GH_REACTION_LAUGH = "laugh"
GH_REACTION_CONFUSED = "confused"
GH_REACTION_HEART = "heart"
GH_REACTION_HOORAY = "hooray"
GH_REACTION_ROCKET = "rocket"
GH_REACTION_EYES = "eyes"


class BackportTaskStatus(str, enum.Enum):
    """Status strings for backport tasks on a release tracking issue."""

    PENDING = "pending"
    DONE = "done"
    RESOLVED = "resolved"
    OPEN_PR = "open-pr"
    DRAFT_PR = "draft-pr"
    ERROR_NOT_FOUND = "error-not-found"
    ERROR_CLOSED_PR = "error-closed-pr"
    ERROR_NO_MERGE_COMMIT = "error-no-merge-commit"
    ERROR_UNKNOWN = "error-unknown"
    ERROR_RESOLUTION_FAILED = "error-resolution-failed"
    ERROR_MERGE_CONFLICT = "error-merge-conflict"
    ERROR_INVALID_PR = "error-invalid-pr"
    IGNORE = "ignore"

    def __str__(self) -> str:
        return self.value


class IssueDict(TypedDict, total=False):
    """In-memory representation of a GitHub Issue object.

    See GitHub API docs:
    https://docs.github.com/en/rest/issues/issues#get-an-issue
    """

    number: int
    title: str
    body: str
    labels: list[str]
    url: str


class AutoMergeDict(TypedDict, total=False):
    """Representation of auto-merge status on a Pull Request.

    See GitHub API docs:
    https://docs.github.com/en/rest/pulls/pulls#get-a-pull-request
    """

    merge_method: str


class PrDict(TypedDict, total=False):
    """In-memory representation of a GitHub Pull Request object.

    See GitHub API docs:
    https://docs.github.com/en/rest/pulls/pulls#get-a-pull-request
    """

    number: int
    title: str
    body: str
    base: str
    head: str
    labels: list[str]
    url: str
    state: str
    isDraft: bool
    mergeCommit: dict[str, str]
    auto_merge: AutoMergeDict | None


class MultipleTrackingIssuesError(ValueError):
    """Raised when multiple open tracking issues are found for a version."""

    pass


class NoTrackingIssueError(ValueError):
    """Raised when no open tracking issue is found for a version."""

    pass


class GitHub:
    """GitHub CLI helper class for the release tool."""

    def __init__(self, repo: str = "bazel-contrib/rules_python"):
        """Initializes the GitHub helper.

        Args:
            repo: The GitHub repository to operate on.
        """
        self.repo = repo

    def _run_gh(
        self, *args: str, check: bool = True, capture_output: bool = True
    ) -> str | None:
        """Runs a 'gh' command.

        Args:
            *args: Arguments for 'gh' (excluding 'gh').
            check: If True, raises CalledProcessError on failure.
            capture_output: If True, captures and returns stdout.

        Returns:
            The stdout of the command, stripped, or None.
        """
        return run_cmd("gh", *args, check=check, capture_output=capture_output)

    def _gh_issue(
        self, *args: str, check: bool = True, capture_output: bool = True
    ) -> str | None:
        """Runs a 'gh issue' command."""
        return self._run_gh(
            "issue",
            *args,
            f"--repo={self.repo}",
            check=check,
            capture_output=capture_output,
        )

    def _gh_pr(
        self, *args: str, check: bool = True, capture_output: bool = True
    ) -> str | None:
        """Runs a 'gh pr' command."""
        return self._run_gh(
            "pr",
            *args,
            f"--repo={self.repo}",
            check=check,
            capture_output=capture_output,
        )

    def list_issues(
        self,
        *,
        fields: str,
        label: str | None = None,
        state: str | None = None,
        search: str | None = None,
    ) -> list[IssueDict]:
        """Helper to list issues using gh CLI.

        Args:
            fields: Comma-separated list of fields to return.
            label: Filter by label.
            state: Filter by state ('open', 'closed', 'all').
            search: Search query.

        Returns:
            A list of issue dictionaries.
        """
        cmd = ["list", f"--json={fields}"]
        if label:
            cmd.append(f"--label={label}")
        if state:
            cmd.append(f"--state={state}")
        if search:
            cmd.append(f"--search={search}")

        output = self._gh_issue(*cmd)
        return json.loads(output) if output else []

    def get_open_tracking_issues(self, version: str | None = None) -> list[IssueDict]:
        """Finds open tracking issues for release.

        Args:
            version: Optional specific version to match (e.g., "1.0.0").

        Returns:
            List of matching open release tracking issue dictionaries.
        """
        search = f"Release {version}" if version else None
        return self.list_issues(
            fields="number,title,url",
            label=RELEASE_LABEL,
            state="open",
            search=search,
        )

    def get_release_tracking_issue(self, version: str) -> int:
        """Finds the single open tracking issue for a given version.

        Args:
            version: Version string (e.g. "1.0.0").

        Returns:
            The issue number.

        Raises:
            NoTrackingIssueError: If no open tracking issue is found.
            MultipleTrackingIssuesError: If multiple open tracking issues are found.
        """
        issues = self.get_open_tracking_issues(version)
        matching = [i for i in issues if i["title"] == f"Release {version}"]
        if not matching:
            raise NoTrackingIssueError(
                f"No open tracking issue found for Release {version}"
            )
        if len(matching) > 1:
            raise MultipleTrackingIssuesError(
                f"Multiple open tracking issues found for Release {version}: "
                + ", ".join(str(i["number"]) for i in matching)
            )
        return matching[0]["number"]

    def create_issue(
        self, title: str, body: str, labels: list[str] | None = None
    ) -> int:
        """Creates an issue using gh CLI.

        Args:
            title: Title of the issue.
            body: Body of the issue.
            labels: List of labels to add.

        Returns:
            The issue number.
        """
        cmd = ["create", f"--title={title}", f"--body={body}"]
        if labels:
            for label in labels:
                cmd.append(f"--label={label}")

        output = self._gh_issue(*cmd)
        if not output:
            raise RuntimeError("gh issue create returned no output")
        # output is URL: https://github.com/owner/repo/issues/123
        return int(output.rstrip("/").split("/")[-1])

    def create_release_tracking_issue(self, version: str, template_content: str) -> int:
        """Creates a release tracking issue from a template.

        Args:
            version: Release version string (e.g., "1.0.0").
            template_content: Content of the issue template markdown file.

        Returns:
            The created issue number.
        """
        title = f"Release {version}"
        # Strip YAML frontmatter if present
        issue_body = template_content
        if template_content.startswith("---"):
            parts = template_content.split("---", 2)
            if len(parts) >= 3:
                issue_body = parts[2].strip()

        return self.create_issue(title=title, body=issue_body, labels=[RELEASE_LABEL])

    def get_issue_body(self, issue_num: int) -> str:
        """Gets the body content of an issue.

        Args:
            issue_num: The issue number.

        Returns:
            The body string of the issue.
        """
        output = self._gh_issue("view", str(issue_num), "--json=body")
        if not output:
            return ""
        data = json.loads(output)
        return data.get("body", "")

    def get_issue_title(self, issue_num: int) -> str:
        """Gets the title of an issue.

        Args:
            issue_num: The issue number.

        Returns:
            The title string of the issue.
        """
        output = self._gh_issue("view", str(issue_num), "--json=title")
        if not output:
            return ""
        data = json.loads(output)
        return data.get("title", "")

    def update_issue_body(self, issue_num: int, body: str) -> None:
        """Updates the body of an issue.

        Args:
            issue_num: The issue number.
            body: The new body content.
        """
        with tempfile.NamedTemporaryFile("w", delete=False, mode="w") as f:
            f.write(body)
            f.flush()
            temp_path = f.name

        try:
            self._gh_issue(
                "edit", str(issue_num), f"--body-file={temp_path}", capture_output=False
            )
        finally:
            if os.path.exists(temp_path):
                os.remove(temp_path)

    def resolve_pr_number(self, pr_ref: str) -> int:
        """Resolves a PR reference (number, #number, or GitHub URL) to a PR number.

        Args:
            pr_ref: PR number string (e.g., "123", "#123") or URL.

        Returns:
            The integer PR number.

        Raises:
            ValueError: If the PR reference cannot be resolved or is for another repo.
        """
        clean_ref = pr_ref.lstrip("#")
        if clean_ref.isdigit():
            return int(clean_ref)

        if pr_ref.startswith("http"):
            pattern = rf"github\.com/{re.escape(self.repo)}/pull/(\d+)(/|\?|\Z)"
            match = re.search(pattern, pr_ref, re.IGNORECASE)
            if match:
                return int(match.group(1))
            raise ValueError(
                f"URL is not for the configured repository ({self.repo}): {pr_ref}"
            )

        raise ValueError(f"Could not resolve PR reference: {pr_ref}")

    def get_pr_info(self, pr_num: int) -> PrDict:
        """Gets info about a PR using gh CLI.

        Args:
            pr_num: The PR number.

        Returns:
            Dictionary containing PR fields (state, isDraft, mergeCommit, etc.).
        """
        output = self._gh_pr("view", str(pr_num), "--json=state,isDraft,mergeCommit")
        return json.loads(output) if output else {}

    def get_pr_comments(self, pr_num: int) -> list[dict]:
        """Gets all comments for a PR using gh CLI.

        Args:
            pr_num: The PR number.

        Returns:
            List of comment objects (with body, author, etc.).
        """
        output = self._gh_pr("view", str(pr_num), "--json=comments")
        if not output:
            return []
        data = json.loads(output)
        return data.get("comments", [])

    def create_pr(
        self,
        title: str,
        body: str,
        base: str = "main",
        labels: list[str] | None = None,
    ) -> str:
        """Creates a pull request.

        Args:
            title: Title of the PR.
            body: Body of the PR.
            base: Base branch to merge into (default: "main").
            labels: Optional list of labels to add.

        Returns:
            The URL of the created PR.
        """
        cmd = [
            "create",
            f"--title={title}",
            f"--body={body}",
            f"--base={base}",
        ]
        if labels:
            for label in labels:
                cmd.append(f"--label={label}")
        output = self._gh_pr(*cmd)
        return output if output else ""

    def enable_auto_merge(self, pr_num: int, method: str = "squash") -> None:
        """Enables auto-merge for a PR.

        Args:
            pr_num: The PR number.
            method: The merge method ('squash', 'rebase', or 'merge').
        """
        cmd = ["merge", str(pr_num), "--auto"]
        if method == "squash":
            cmd.append("--squash")
        elif method == "rebase":
            cmd.append("--rebase")
        elif method == "merge":
            cmd.append("--merge")
        self._gh_pr(*cmd, capture_output=False)

    def get_open_pr(self, branch_name: str) -> PrDict | None:
        """Finds an open PR for the given branch.

        Args:
            branch_name: The head branch name to search for.

        Returns:
            Dictionary with 'number' and 'url' if an open PR exists, else None.
        """
        cmd = [
            "list",
            f"--head={branch_name}",
            "--state=open",
            "--json=number,url",
        ]
        output = self._gh_pr(*cmd)
        prs = json.loads(output) if output else []
        return prs[0] if prs else None

    def post_issue_comment(self, issue_num: int, comment_body: str) -> None:
        """Posts a comment on an issue or PR.

        Args:
            issue_num: The issue or PR number.
            comment_body: The body content of the comment.
        """
        self._gh_issue(
            "comment",
            str(issue_num),
            f"--body={comment_body}",
            capture_output=False,
        )

    def add_comment_reaction(self, comment_id: int, reaction: str) -> None:
        """Adds a reaction to an issue or PR comment.

        Args:
            comment_id: The comment ID (note: gh api endpoint needed for comment reactions).
            reaction: The reaction type (e.g., "+1", "-1", "rocket").
        """
        self._run_gh(
            "api",
            f"repos/{self.repo}/issues/comments/{comment_id}/reactions",
            "-f",
            f"content={reaction}",
            capture_output=False,
        )

    def get_merge_commits_for_prs(
        self, pending_items: list[BackportTask]
    ) -> list[BackportTask]:
        """Resolves PR references in pending backports to their merge commit SHAs.

        Updates item.status based on PR state if it cannot be resolved.

        Args:
            pending_items: A list of BackportTask items to resolve.

        Returns:
            The list of resolved BackportTask items.
        """
        return resolve_merge_commits_for_prs(self, pending_items)


def resolve_merge_commits_for_prs(
    gh_client: GitHub, pending_items: list[BackportTask]
) -> list[BackportTask]:
    """Resolves PR references in pending backports to their merge commit SHAs.

    Updates item.status based on PR state if it cannot be resolved.

    Args:
        gh_client: The GitHub client.
        pending_items: A list of BackportTask items to resolve.

    Returns:
        The list of resolved BackportTask items.
    """
    resolved_items = []
    for item in pending_items:
        pr_num = int(item.pr_ref.lstrip("#"))
        print(f"Resolving PR #{pr_num} to merge commit...")
        try:
            pr_info = gh_client.get_pr_info(pr_num)
            if not pr_info:
                print(f"PR #{pr_num} not found. Gating.")
                item.status = BackportTaskStatus.ERROR_NOT_FOUND
            else:
                state = pr_info.get("state")
                is_draft = pr_info.get("isDraft", False)
                if state == "OPEN" or is_draft:
                    print(
                        f"PR #{pr_num} is open or draft (state: {state},"
                        f" draft: {is_draft}). Ignoring."
                    )
                    item.status = (
                        BackportTaskStatus.OPEN_PR
                        if not is_draft
                        else BackportTaskStatus.DRAFT_PR
                    )
                elif state == "CLOSED":
                    print(f"PR #{pr_num} is closed but not merged. Gating.")
                    item.status = BackportTaskStatus.ERROR_CLOSED_PR
                elif state == "MERGED":
                    merge_commit = pr_info.get("mergeCommit")
                    if merge_commit and "oid" in merge_commit:
                        item.commit = merge_commit["oid"]
                        item.status = BackportTaskStatus.RESOLVED
                    else:
                        print(f"PR #{pr_num} has no merge commit SHA. Gating.")
                        item.status = BackportTaskStatus.ERROR_NO_MERGE_COMMIT
                else:
                    print(f"PR #{pr_num} has unknown state: {state}. Gating.")
                    item.status = BackportTaskStatus.ERROR_UNKNOWN
        except Exception as e:
            print(f"Error resolving PR #{pr_num}: {e}. Gating.")
            item.status = BackportTaskStatus.ERROR_RESOLUTION_FAILED
        resolved_items.append(item)
    return resolved_items

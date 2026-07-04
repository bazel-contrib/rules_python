"""GitHub CLI helper functions for the release tool."""

import json
import os
import re
import tempfile

from tools.private.release.release_issue import BackportTask
from tools.private.release.shell import run_cmd

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
        self.label = "type: release"

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
    ) -> list[dict]:
        """Helper to list issues using gh CLI.

        Args:
            fields: Comma-separated list of fields to return.
            label: Filter by label.
            state: Filter by state (open, closed, all).
            search: Search query.

        Returns:
            A list of dictionaries representing the issues.
        """
        cmd = ["list"]
        if label:
            cmd.append(f"--label={label}")
        if state:
            cmd.append(f"--state={state}")
        if search:
            cmd.append(f"--search={search}")
        cmd.append(f"--json={fields}")

        output = self._gh_issue(*cmd)
        return json.loads(output) if output else []

    def get_open_tracking_issues(self, version: str | None = None) -> list[dict]:
        """Returns a list of open tracking issues with the 'type: release' label.

        Args:
            version: Optional version to filter by.

        Returns:
            A list of open tracking issues.
        """
        search = f'"Release {version}" in:title' if version else None
        return self.list_issues(
            label=self.label,
            state="open",
            search=search,
            fields="number,title,url",
        )

    def get_release_tracking_issue(self, version: str) -> int:
        """Resolves the tracking issue number for a given version.

        Searches for an open issue with label 'type: release' and 'Release
        <version>' in the title.

        Args:
            version: The version to find the tracking issue for.

        Returns:
            The tracking issue number.

        Raises:
            NoTrackingIssueError: If no open tracking issue is found.
            MultipleTrackingIssuesError: If multiple open tracking issues are
              found.
        """
        matching_issues = self.get_open_tracking_issues(version)

        exact_matches = []
        for issue in matching_issues:
            if issue["title"] == f"Release {version}":
                exact_matches.append(issue)

        if not exact_matches:
            raise NoTrackingIssueError(
                f"No open tracking issue found matching 'Release {version}' "
                f"in repo {self.repo} with label '{self.label}'"
            )
        if len(exact_matches) > 1:
            urls = [issue["url"] for issue in exact_matches]
            raise MultipleTrackingIssuesError(
                f"Multiple open tracking issues found for version {version} "
                f"in repo {self.repo} with label '{self.label}':\n" + "\n".join(urls)
            )

        return exact_matches[0]["number"]

    def create_tracking_issue(self, version: str, template_content: str) -> int:
        """Creates a new release tracking issue from template content.

        Strips YAML frontmatter if present.

        Args:
            version: The version to create the tracking issue for.
            template_content: The markdown template content for the issue body.

        Returns:
            The created issue number.
        """
        # Strip YAML frontmatter if present
        issue_body = template_content
        if template_content.startswith("---"):
            parts = template_content.split("---", 2)
            if len(parts) >= 3:
                issue_body = parts[2].strip()

        # Write body to a secure temporary file to pass to the CLI
        with tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False) as f:
            f.write(issue_body)
            temp_path = f.name

        try:
            output = self._gh_issue(
                "create",
                f"--title=Release {version}",
                f"--label={self.label}",
                f"--body-file={temp_path}",
            )
            if not output:
                raise RuntimeError("Failed to get issue URL from gh issue create")
            issue_url = output.strip()
            issue_num = int(issue_url.split("/")[-1])
            return issue_num
        finally:
            if os.path.exists(temp_path):
                os.unlink(temp_path)

    def get_issue_body(self, issue_num: int) -> str:
        """Fetches the body of a specific issue.

        Args:
            issue_num: The issue number.

        Returns:
            The issue body markdown.
        """
        output = self._gh_issue(
            "view",
            str(issue_num),
            "--json=body",
            "--jq=.body",
        )
        return output if output else ""

    def get_issue_title(self, issue_num: int) -> str:
        """Fetches the title of a specific issue.

        Args:
            issue_num: The issue number.

        Returns:
            The issue title.
        """
        output = self._gh_issue(
            "view",
            str(issue_num),
            "--json=title",
        )
        return json.loads(output)["title"] if output else ""

    def update_issue_body(self, issue_num: int, body: str) -> None:
        """Updates the body of a specific issue.

        Args:
            issue_num: The issue number.
            body: The new issue body markdown.
        """
        with tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False) as f:
            f.write(body)
            temp_path = f.name
        try:
            self._gh_issue(
                "edit",
                str(issue_num),
                f"--body-file={temp_path}",
                capture_output=False,
            )
        finally:
            if os.path.exists(temp_path):
                os.unlink(temp_path)

    def create_pr(self, version: str, issue_num: int) -> str:
        """Creates a pull request for release preparation.

        Args:
            version: The version being prepared.
            issue_num: The associated tracking issue number.

        Returns:
            The URL of the created PR.
        """
        output = self._gh_pr(
            "create",
            f"--title=Prepare release v{version}",
            f"--body=Work towards #{issue_num}",
            "--base=main",
        )
        return output if output else ""

    def get_open_pr(self, branch_name: str) -> dict | None:
        """Returns PR info if an open PR exists for the given branch.

        Args:
            branch_name: The head branch name of the PR.

        Returns:
            A dictionary with 'number' and 'url' of the PR, or None.
        """
        output = self._gh_pr(
            "list",
            f"--head={branch_name}",
            "--state=open",
            "--json=number,url",
        )
        prs = json.loads(output) if output else []
        return prs[0] if prs else None

    def get_pr_info(self, pr_num: int) -> dict:
        """Gets information about a PR.

        Includes state, merge commit, body, and draft status.

        Args:
            pr_num: The PR number.

        Returns:
            A dictionary containing the PR info.
        """
        output = self._gh_pr(
            "view",
            str(pr_num),
            "--json=state,mergeCommit,body,isDraft",
        )
        return json.loads(output) if output else {}

    def get_pr_comments(self, pr_num: int) -> list[dict]:
        """Gets comments for a PR.

        Args:
            pr_num: The PR number.

        Returns:
            A list of comments.
        """
        output = self._gh_pr(
            "view",
            str(pr_num),
            "--json=comments",
        )
        return json.loads(output).get("comments") or []

    def resolve_pr_number(self, pr_ref: str) -> int:
        """Resolves a PR reference (number, #number, URL) to a PR number.

        Args:
            pr_ref: The PR reference string.

        Returns:
            The resolved PR number.

        Raises:
            ValueError: If the reference cannot be resolved.
        """
        # 1. Try number (e.g. "123" or "#123")
        clean_ref = pr_ref.lstrip("#")
        if clean_ref.isdigit():
            return int(clean_ref)

        # 2. Try URL (starts with http)
        if pr_ref.startswith("http"):
            # Try to extract PR number from URL using regex
            # Pattern matches: github.com/<self.repo>/pull/<number> followed by /, ?, or EOF
            pattern = rf"github\.com/{re.escape(self.repo)}/pull/(\d+)(/|\?|\Z)"
            match = re.search(pattern, pr_ref, re.IGNORECASE)
            if match:
                return int(match.group(1))
            raise ValueError(
                f"URL is not for the configured repository ({self.repo}): {pr_ref}"
            )

        raise ValueError(f"Could not resolve PR reference: {pr_ref}")

    def post_issue_comment(self, issue_num: int, comment_body: str) -> None:
        """Posts a comment to a specific issue.

        Args:
            issue_num: The issue number.
            comment_body: The comment body markdown.
        """
        self._gh_issue(
            "comment",
            str(issue_num),
            f"--body={comment_body}",
            capture_output=False,
        )

    def add_comment_reaction(self, comment_id: int, reaction: str) -> None:
        """Adds a reaction to a comment.

        Args:
            comment_id: The ID of the comment.
            reaction: The reaction type (e.g. '+1', '-1', 'eyes', etc).
        """
        path = f"/repos/{self.repo}/issues/comments/{comment_id}/reactions"
        self._run_gh(
            "api",
            "--method",
            "POST",
            "-H",
            "Accept: application/vnd.github+json",
            "-H",
            "X-GitHub-Api-Version: 2022-11-28",
            path,
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
        resolved_items = []
        for item in pending_items:
            pr_num = int(item.pr_ref.lstrip("#"))
            print(f"Resolving PR #{pr_num} to merge commit...")
            try:
                pr_info = self.get_pr_info(pr_num)
                if not pr_info:
                    print(f"PR #{pr_num} not found. Gating.")
                    item.status = "error-not-found"
                else:
                    state = pr_info.get("state")
                    is_draft = pr_info.get("isDraft", False)
                    if state == "OPEN" or is_draft:
                        print(
                            f"PR #{pr_num} is open or draft (state: {state},"
                            f" draft: {is_draft}). Ignoring."
                        )
                        item.status = "open-pr" if not is_draft else "draft-pr"
                    elif state == "CLOSED":
                        print(f"PR #{pr_num} is closed but not merged. Gating.")
                        item.status = "error-closed-pr"
                    elif state == "MERGED":
                        merge_commit = pr_info.get("mergeCommit")
                        if merge_commit and "oid" in merge_commit:
                            item.commit = merge_commit["oid"]
                            item.status = "resolved"
                        else:
                            print(f"PR #{pr_num} has no merge commit SHA. Gating.")
                            item.status = "error-no-merge-commit"
                    else:
                        print(f"PR #{pr_num} has unknown state: {state}. Gating.")
                        item.status = "error-unknown"
            except Exception as e:
                print(f"Error resolving PR #{pr_num}: {e}. Gating.")
                item.status = "error-resolution-failed"
            resolved_items.append(item)
        return resolved_items

"""In-memory fake for GitHub API."""

import re

from tools.private.release.gh import (
    RELEASE_LABEL,
    IssueDict,
    MultipleTrackingIssuesError,
    NoTrackingIssueError,
    PrDict,
    resolve_merge_commits_for_prs,
)


class MockGitHub:
    def __init__(self, repo: str = "bazel-contrib/rules_python"):
        self.repo = repo
        self.issues: dict[int, IssueDict] = {}
        self.next_issue_num = 1001
        self.prs: dict[int, PrDict] = {}  # num -> pr_info
        self.issue_comments: dict[int, list[str]] = {}
        self.reactions: dict[int, list[str]] = {}
        self.pr_comments: dict[int, list[dict]] = {}

    def post_issue_comment(self, issue_num: int, comment_body: str) -> None:
        self.issue_comments.setdefault(issue_num, []).append(comment_body)

    def add_comment_reaction(self, comment_id: int, reaction: str) -> None:
        self.reactions.setdefault(comment_id, []).append(reaction)

    def enable_auto_merge(self, pr_num: int, method: str = "squash") -> None:
        if pr_num not in self.prs:
            self.create_pr(title="", body="")
        self.prs[pr_num]["auto_merge"] = {"merge_method": method}

    def create_issue(
        self, title: str, body: str, labels: list[str] | None = None
    ) -> int:
        issue_num = self.next_issue_num
        self.next_issue_num += 1
        self.issues[issue_num] = {
            "title": title,
            "body": body,
            "labels": labels or [],
            "number": issue_num,
            "url": f"https://github.com/{self.repo}/issues/{issue_num}",
        }
        return issue_num

    def create_release_tracking_issue(self, version: str, template_content: str) -> int:
        # Strip YAML frontmatter if present (simplified copy from gh.py)
        issue_body = template_content
        if template_content.startswith("---"):
            parts = template_content.split("---", 2)
            if len(parts) >= 3:
                issue_body = parts[2].strip()

        return self.create_issue(
            title=f"Release {version}", body=issue_body, labels=[RELEASE_LABEL]
        )

    def get_issue_body(self, issue_num: int) -> str:
        if issue_num not in self.issues:
            raise ValueError(f"Issue #{issue_num} not found in MockGitHub")
        return self.issues[issue_num]["body"]

    def get_issue_title(self, issue_num: int) -> str:
        if issue_num not in self.issues:
            raise ValueError(f"Issue #{issue_num} not found in MockGitHub")
        return self.issues[issue_num]["title"]

    def update_issue_body(self, issue_num: int, body: str):
        if issue_num not in self.issues:
            raise ValueError(f"Issue #{issue_num} not found in MockGitHub")
        self.issues[issue_num]["body"] = body

    def resolve_pr_number(self, pr_ref: str) -> int:
        # Real algorithm copy (doesn't require RPCs)
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
        raise ValueError(f"Could not resolve PR ref: {pr_ref}")

    def get_release_tracking_issue(self, version: str) -> int:
        search_title = f"Release {version}"
        matching = [
            num
            for num, issue in self.issues.items()
            if issue["title"] == search_title
            and RELEASE_LABEL in issue.get("labels", [])
        ]
        if not matching:
            raise NoTrackingIssueError(
                f"No open tracking issue found for Release {version}"
            )
        if len(matching) > 1:
            raise MultipleTrackingIssuesError(
                f"Multiple open tracking issues found for Release {version}"
            )
        return matching[0]

    def create_pr(
        self,
        title: str,
        body: str,
        base: str = "main",
        labels: list[str] | None = None,
    ) -> str:
        pr_num = self.next_issue_num
        self.next_issue_num += 1
        url = f"https://github.com/{self.repo}/pull/{pr_num}"
        self.prs[pr_num] = {
            "title": title,
            "body": body,
            "base": base,
            "labels": labels or [],
            "number": pr_num,
            "url": url,
            "state": "OPEN",
        }
        return url

    def get_open_pr(self, branch_name: str) -> PrDict | None:
        for pr in self.prs.values():
            if pr.get("head") == branch_name and pr.get("state") == "OPEN":
                return pr
        return None

    def get_open_tracking_issues(self, version: str | None = None) -> list[IssueDict]:
        results = []
        for issue in self.issues.values():
            if RELEASE_LABEL in issue["labels"]:
                if version:
                    if issue["title"] == f"Release {version}":
                        results.append(issue)
                else:
                    results.append(issue)
        return results

    def get_pr_info(self, pr_num: int) -> PrDict:
        if pr_num in self.prs:
            return self.prs[pr_num]
        return {
            "state": "MERGED",
            "mergeCommit": {"oid": f"mock_merge_sha_{pr_num}"},
        }

    def get_pr_comments(self, pr_num: int) -> list[dict]:
        return self.pr_comments.get(pr_num, [])

    def get_merge_commits_for_prs(self, pending_items: list) -> list:
        return resolve_merge_commits_for_prs(self, pending_items)

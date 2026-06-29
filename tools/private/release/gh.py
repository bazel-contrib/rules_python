"""GitHub CLI helper functions for the release tool."""

import json
import os
import tempfile

from tools.private.release.shell import run_cmd

_REPO = "bazel-contrib/rules_python"
_LABEL = "type: release"


class MultipleTrackingIssuesError(ValueError):
    """Raised when multiple open tracking issues are found for a version."""

    pass


class NoTrackingIssueError(ValueError):
    """Raised when no open tracking issue is found for a version."""

    pass


def list_issues(*, fields, label=None, state=None, search=None):
    """Helper to list issues using gh CLI."""
    cmd = ["gh", "issue", "list", f"--repo={_REPO}"]
    if label:
        cmd.append(f"--label={label}")
    if state:
        cmd.append(f"--state={state}")
    if search:
        cmd.append(f"--search={search}")
    cmd.append(f"--json={fields}")

    output = run_cmd(*cmd)
    return json.loads(output) if output else []


def get_open_tracking_issues(version=None):
    """Returns a list of open tracking issues with the 'type: release' label."""
    search = f'"Release {version}" in:title' if version else None
    return list_issues(
        label=_LABEL,
        state="open",
        search=search,
        fields="number,title,url",
    )


def get_release_tracking_issue(version):
    """Resolves the tracking issue number for a given version.

    Searches for an open issue with label 'type: release' and 'Release <version>' in the title.
    Raises ValueError if 0 or multiple issues are found.
    """
    matching_issues = get_open_tracking_issues(version)

    exact_matches = []
    for issue in matching_issues:
        if issue["title"] == f"Release {version}":
            exact_matches.append(issue)

    if not exact_matches:
        raise NoTrackingIssueError(
            f"No open tracking issue found matching 'Release {version}' "
            f"in repo {_REPO} with label '{_LABEL}'"
        )
    if len(exact_matches) > 1:
        urls = [issue["url"] for issue in exact_matches]
        raise MultipleTrackingIssuesError(
            f"Multiple open tracking issues found for version {version} "
            f"in repo {_REPO} with label '{_LABEL}':\n" + "\n".join(urls)
        )

    return exact_matches[0]["number"]


def create_tracking_issue(version, template_content):
    """Creates a new release tracking issue from template content (strips YAML frontmatter)."""
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
        output = run_cmd(
            "gh",
            "issue",
            "create",
            f"--title=Release {version}",
            f"--label={_LABEL}",
            f"--body-file={temp_path}",
        )
        issue_url = output.strip()
        issue_num = int(issue_url.split("/")[-1])
        return issue_num
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)


def get_issue_body(issue_num):
    """Fetches the body of a specific issue."""
    return run_cmd(
        "gh",
        "issue",
        "view",
        str(issue_num),
        "--json=body",
        "--jq=.body",
    )


def get_issue_title(issue_num):
    """Fetches the title of a specific issue."""
    output = run_cmd(
        "gh",
        "issue",
        "view",
        str(issue_num),
        "--json=title",
    )
    return json.loads(output)["title"] if output else ""


def update_issue_body(issue_num, body):
    """Updates the body of a specific issue."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False) as f:
        f.write(body)
        temp_path = f.name
    try:
        run_cmd(
            "gh",
            "issue",
            "edit",
            str(issue_num),
            f"--body-file={temp_path}",
            capture_output=False,
        )
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)


def create_pr(version, issue_num):
    """Creates a pull request for release preparation."""
    return run_cmd(
        "gh",
        "pr",
        "create",
        f"--title=Prepare release v{version}",
        f"--body=Work towards #{issue_num}",
        "--base=main",
    )


def get_pr_info(pr_num):
    """Gets information about a PR, including state, merge commit, and body."""
    output = run_cmd(
        "gh",
        "pr",
        "view",
        str(pr_num),
        "--json=state,mergeCommit,body",
    )
    return json.loads(output) if output else {}


def post_issue_comment(issue_num, comment_body):
    """Posts a comment to a specific issue."""
    run_cmd(
        "gh",
        "issue",
        "comment",
        str(issue_num),
        f"--body={comment_body}",
        capture_output=False,
    )


def resolve_backport_commits(pending_items):
    """Resolves PR references in pending backports to their merge commit SHAs.

    Marks unmerged PRs or resolution failures with status='unmerged-pr'.
    """
    resolved_items = []
    for item in pending_items:
        pr_num = item["pr_ref"].lstrip("#")
        print(f"Resolving PR #{pr_num} to merge commit...")
        try:
            pr_info = get_pr_info(pr_num)
            if not pr_info or pr_info.get("state") != "MERGED":
                state = pr_info.get("state", "UNKNOWN")
                print(f"PR #{pr_num} is not merged (state: {state}). Gating.")
                item["status"] = "unmerged-pr"
            else:
                merge_commit = pr_info.get("mergeCommit")
                if merge_commit and "oid" in merge_commit:
                    item["commit"] = merge_commit["oid"]
                else:
                    print(f"PR #{pr_num} has no merge commit SHA. Gating.")
                    item["status"] = "unmerged-pr"
        except Exception as e:
            print(f"Error resolving PR #{pr_num}: {e}. Gating.")
            item["status"] = "unmerged-pr"
        resolved_items.append(item)
    return resolved_items

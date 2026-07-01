"""A tool to perform release steps."""

import argparse
import os
import pathlib
import re
import sys

from tools.private.release import gh, git
from tools.private.release.create_rc import cmd_create_rc
from tools.private.release.create_release_branch import cmd_create_release_branch
from tools.private.release.prepare import cmd_prepare
from tools.private.release.process_backports import cmd_process_backports
from tools.private.release.release_issue import (
    update_task_in_body,
)
from tools.private.release.utils import (
    REPO_URL,
    determine_next_version,
    get_latest_rc_tag,
)


def _semver_type(value):
    if not re.match(r"^\d+\.\d+\.\d+(rc\d+)?$", value):
        raise argparse.ArgumentTypeError(
            f"'{value}' is not a valid semantic version (X.Y.Z or X.Y.ZrcN)"
        )
    return value


# ==============================================================================
# Subcommand Execution Functions
# ==============================================================================


def cmd_determine_next_version(args):
    """Executes the determine-next-version subcommand."""
    version = determine_next_version()
    print(version)
    return 0


def cmd_create_release_issue(args):
    """Executes the create-release-issue subcommand."""
    version = args.version
    if version is None:
        version = determine_next_version()

    # Concurrency check
    open_issues = gh.get_open_tracking_issues()
    if open_issues:
        print("Error: A release is already in progress. Active tracking issues:")
        for issue in open_issues:
            print(f"- {issue['title']}: {issue['url']}")
        return 1

    template_path = pathlib.Path(".github/ISSUE_TEMPLATE/release_tracking_template.md")
    if not template_path.exists():
        raise FileNotFoundError(f"Template file not found at {template_path}")
    template_content = template_path.read_text(encoding="utf-8")

    issue_num = gh.create_tracking_issue(version, template_content)
    print(f"Created tracking issue #{issue_num} for v{version}")
    return 0


def cmd_complete_prepare(args):
    """Executes the complete-prepare subcommand (Phase 2 PR merged)."""
    print(f"Completing preparation for PR #{args.pr}...")

    pr_info = gh.get_pr_info(args.pr)
    if not pr_info or pr_info.get("state") != "MERGED":
        state = pr_info.get("state", "UNKNOWN")
        print(f"Error: PR #{args.pr} is not merged yet (state: {state}).")
        return 1

    # Resolve issue number from PR body
    pr_body = pr_info.get("body", "")
    match = re.search(r"Work towards #(\d+)", pr_body)
    if not match:
        match = re.search(r"#(\d+)", pr_body)
    if not match:
        print(
            f"Error: Could not determine tracking issue number from PR #{args.pr}"
            f" body: {pr_body}"
        )
        return 1

    issue_num = int(match.group(1))
    print(f"Resolved tracking issue #{issue_num} from PR #{args.pr} body.")

    commit_sha = pr_info["mergeCommit"]["oid"]
    short_commit = commit_sha[:8]
    print(f"PR #{args.pr} merged at commit {commit_sha}. Updating tracking issue...")

    # Update checklist: mark Prepare Release as done (checked) and set SUCCESS
    body = gh.get_issue_body(issue_num)
    metadata = {"status": "done", "pr": f"#{args.pr}", "commit": short_commit}
    updated_body = update_task_in_body(
        body, "Prepare Release", checked=True, metadata=metadata
    )
    gh.update_issue_body(issue_num, updated_body)
    print("Prepare Release task marked complete successfully!")
    return 0


def cmd_promote_rc(args):
    """Executes the promote-rc subcommand (Phase 3)."""
    # Fetch from upstream to ensure we have the latest tags
    git.fetch("upstream", tags=True, force=True)

    version = args.version
    if version is None:
        version = determine_next_version()

    latest_rc = get_latest_rc_tag(version, remote="upstream")
    if not latest_rc:
        print(f"Error: No release candidate tags found matching {version}-rc*")
        return 1

    # Verify final tag doesn't already exist
    if git.tag_exists(version):
        print(f"Error: Final tag {version} already exists.")
        return 1

    # Verify issue can be found
    issue_num = args.issue
    if not issue_num:
        try:
            issue_num = gh.get_release_tracking_issue(version)
        except ValueError as e:
            print(f"Error: {e}")
            return 1
        except Exception as e:
            print(f"Error: Unexpected error finding tracking issue: {e}")
            return 1

    # Get commit SHA of the RC tag (which will be the same for the final tag)
    commit_sha = git.get_commit_sha(latest_rc)

    # Verify issue is in the right format by trying to prepare the update
    print(f"Verifying tracking issue #{issue_num} format...")
    body = gh.get_issue_body(issue_num)
    metadata = {"status": "done", "tag": version, "commit": commit_sha[:8]}
    try:
        updated_body = update_task_in_body(
            body, "Tag Final", checked=True, metadata=metadata
        )
    except ValueError as e:
        print(f"Error: Tracking issue #{issue_num} is malformed: {e}")
        return 1

    # All pre-conditions met, perform modifications
    if args.dry_run:
        print(
            f"[DRY RUN] Pre-conditions passed successfully for promoting {latest_rc} to {version}."
        )
        print(f"[DRY RUN] Would tag commit {commit_sha[:8]} as {version}")
        print(f"[DRY RUN] Would push tag {version} to upstream")
        print(f"[DRY RUN] Would update tracking issue #{issue_num} checklist")
        print(f"[DRY RUN] Would post comment to tracking issue #{issue_num}")
        return 0

    print(
        f"Promoting {latest_rc} to final release {version} (commit"
        f" {commit_sha[:8]}) using tracking issue #{issue_num}..."
    )

    # Tag the specific commit without checkout, and push to upstream
    git.tag(version, commit_sha)
    git.push("upstream", version)

    print(f"Updating tracking issue #{issue_num} checklist...")
    gh.update_issue_body(issue_num, updated_body)

    print(f"Posting comment to tracking issue #{issue_num}...")
    import urllib.parse

    release_url = f"{REPO_URL}/releases/tag/{version}"
    bcr_query = f'is:pr ("bazel-contrib/rules_python" in:title) ("@{version}" in:title)'
    bcr_search_url = f"https://github.com/bazelbuild/bazel-central-registry/pulls?q={urllib.parse.quote(bcr_query)}"
    comment_body = (
        f"Version {version} has been tagged.\n\n"
        f"- **Release Page**: {release_url}\n"
        f"- **BCR PR Search**: [{bcr_query}]({bcr_search_url})"
    )
    gh.post_issue_comment(issue_num, comment_body)

    return 0


def create_parser():
    """Creates the argument parser with subcommands."""
    parser = argparse.ArgumentParser(
        description="Automate release steps for rules_python."
    )

    subparsers = parser.add_subparsers(
        dest="command", required=True, help="Subcommands"
    )

    # Subcommand: determine-next-version
    subparsers.add_parser(
        "determine-next-version",
        help="Determine the next version and print it, without making any changes.",
    )

    # Subcommand: create-release-issue
    create_issue_parser = subparsers.add_parser(
        "create-release-issue",
        help="Search for open releases and create a new tracking issue.",
    )
    create_issue_parser.add_argument(
        "--version",
        type=_semver_type,
        help="The release version (e.g., 0.38.0). If not provided, determined automatically.",
    )

    # Subcommand: prepare
    prepare_parser = subparsers.add_parser(
        "prepare",
        help="Prepare the release (updates changelog, placeholders).",
    )
    prepare_parser.add_argument(
        "version",
        nargs="?",
        type=_semver_type,
        help="The new release version (e.g., 0.28.0). If not provided, "
        "it will be determined automatically.",
    )
    prepare_parser.add_argument(
        "--issue",
        type=int,
        help="The tracking issue number (optional, triggers automated branch/PR pipeline).",
    )
    prepare_parser.add_argument(
        "--dry-run",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Perform a dry run (default: True). Use --no-dry-run to actually execute.",
    )

    # Subcommand: complete-prepare
    complete_prep_parser = subparsers.add_parser(
        "complete-prepare",
        help="Mark the Prepare Release task as complete in the tracking issue.",
    )
    complete_prep_parser.add_argument(
        "--pr",
        type=int,
        required=True,
        help="The merged preparation PR number.",
    )

    # Subcommand: create-release-branch
    create_branch_parser = subparsers.add_parser(
        "create-release-branch",
        help="Create the release branch pointing to the merged PR commit.",
    )
    create_branch_parser.add_argument(
        "--issue",
        type=int,
        required=True,
        help="The tracking issue number (required).",
    )
    create_branch_parser.add_argument(
        "--remote",
        type=str,
        required=True,
        help="The git remote to create the branch on (required).",
    )

    # Subcommand: process-backports
    process_backports_parser = subparsers.add_parser(
        "process-backports",
        help="Cherry-pick pending backports listed in the tracking issue.",
    )
    process_backports_parser.add_argument(
        "--issue",
        type=int,
        required=True,
        help="The tracking issue number (required).",
    )
    process_backports_parser.add_argument(
        "--remote",
        type=str,
        required=True,
        help="The git remote to push changes to (required).",
    )
    process_backports_parser.add_argument(
        "--dry-run",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Perform a dry run (default: True). Use --no-dry-run to actually execute.",
    )

    # Subcommand: create-rc
    create_rc_parser = subparsers.add_parser(
        "create-rc",
        help="Tags the next RC on the release branch if no backports remain.",
    )
    create_rc_parser.add_argument(
        "--issue",
        type=int,
        required=True,
        help="The tracking issue number (required).",
    )
    create_rc_parser.add_argument(
        "--remote",
        type=str,
        required=True,
        help="The git remote to push the RC tag to (required).",
    )

    # Subcommand: promote-rc
    promote_parser = subparsers.add_parser(
        "promote-rc",
        help="Promote the latest RC to final release.",
    )
    promote_parser.add_argument(
        "version",
        nargs="?",
        type=_semver_type,
        help="The final version to release (e.g., 0.38.0).",
    )
    promote_parser.add_argument(
        "--issue",
        type=int,
        help="The tracking issue number (optional).",
    )
    promote_parser.add_argument(
        "--dry-run",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Perform a dry run (default: True). Use --no-dry-run to actually execute.",
    )

    return parser


def main():
    if "BUILD_WORKSPACE_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKSPACE_DIRECTORY"])

    parser = create_parser()
    args = parser.parse_args()

    exit_code = 1
    try:
        if args.command == "determine-next-version":
            exit_code = cmd_determine_next_version(args)
        elif args.command == "create-release-issue":
            exit_code = cmd_create_release_issue(args)
        elif args.command == "prepare":
            exit_code = cmd_prepare(args)
        elif args.command == "complete-prepare":
            exit_code = cmd_complete_prepare(args)
        elif args.command == "create-release-branch":
            exit_code = cmd_create_release_branch(args)
        elif args.command == "process-backports":
            exit_code = cmd_process_backports(args)
        elif args.command == "create-rc":
            exit_code = cmd_create_rc(args)
        elif args.command == "promote-rc":
            exit_code = cmd_promote_rc(args)
    except Exception as e:
        print(f"Fatal error executing {args.command}: {e}", file=sys.stderr)
        if hasattr(e, "__notes__"):
            for note in e.__notes__:
                print(note, file=sys.stderr)
        sys.exit(1)

    sys.exit(exit_code if exit_code is not None else 0)


if __name__ == "__main__":
    main()

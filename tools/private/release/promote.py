"""Subcommand to promote a release candidate to final release."""

import argparse
import os
import urllib.parse

from tools.private.release.gh import GitHub
from tools.private.release.git import Git
from tools.private.release.release_issue import (
    RELEASE_TITLE_RE,
    update_task_in_body,
)
from tools.private.release.utils import (
    REPO_URL,
    determine_next_version,
    get_latest_rc_tag,
    semver_type,
)


class Promote:
    """Class to promote a release candidate to final release."""

    def __init__(self, args, git: Git, gh: GitHub):
        self.args = args
        self.git = git
        self.gh = gh

    def run(self) -> int:
        """Executes the promote-rc subcommand (Phase 3)."""
        args = self.args
        # Fetch from remote to ensure we have the latest tags
        self.git.fetch(args.remote, tags=True, force=True)

        version = args.version
        if version is None:
            if args.issue:
                issue_title = self.gh.get_issue_title(args.issue)
                version_match = RELEASE_TITLE_RE.search(issue_title)
                if version_match:
                    version = version_match.group(1)
                    print(
                        f"Resolved version {version} from tracking issue"
                        f" #{args.issue} title."
                    )
                else:
                    print(
                        f"Error: Could not parse version from issue title:"
                        f" {issue_title}"
                    )
                    return 1
            else:
                version = determine_next_version()

        # Verify final tag doesn't already exist
        if self.git.tag_exists(version):
            print(f"Error: Final tag {version} already exists.")
            return 1

        is_first_release = version.endswith(".0")

        # Verify issue can be found
        issue_num = args.issue
        if not issue_num:
            try:
                issue_num = self.gh.get_release_tracking_issue(version)
            except ValueError as e:
                print(f"Error: {e}")
                return 1
            except Exception as e:
                print(f"Error: Unexpected error finding tracking issue: {e}")
                return 1

        if is_first_release:
            latest_rc = get_latest_rc_tag(version, remote=args.remote)
            if not latest_rc:
                print(f"Error: No release candidate tags found matching {version}-rc*")
                return 1
            commit_sha = self.git.get_commit_sha(latest_rc)
        else:
            latest_rc = None

        # Verify issue can be found and read it early
        print(f"Verifying tracking issue #{issue_num} format...")
        body = self.gh.get_issue_body(issue_num)

        # Determine release branch name
        branch_version = ".".join(version.split(".")[:2])
        branch_name = f"release/{branch_version}"
        remote_branch = f"{args.remote}/{branch_name}"

        print(f"Fetching remote branch {remote_branch}...")
        self.git.fetch(args.remote, refspec=branch_name)
        try:
            branch_sha = self.git.get_commit_sha(remote_branch)
        except Exception as e:
            print(
                f"Error: Could not get commit SHA for remote branch"
                f" {remote_branch}: {e}"
            )
            return 1

        if is_first_release:
            if commit_sha != branch_sha:
                print(
                    f"Error: The latest RC tag {latest_rc} ({commit_sha[:8]}) is not at"
                    f" the head of release branch {remote_branch} ({branch_sha[:8]})."
                )
                metadata = {
                    "status": "error-rc-tag-not-branch-head",
                    "rc": latest_rc,
                    "branch_commit": branch_sha[:8],
                    "tag_commit": commit_sha[:8],
                }
                try:
                    updated_body = update_task_in_body(
                        body, "Tag Final", checked=False, metadata=metadata
                    )
                except ValueError as e:
                    print(f"Error: Tracking issue #{issue_num} is malformed: {e}")
                    return 1

                if not args.dry_run:
                    self.gh.update_issue_body(issue_num, updated_body)
                    print(f"Updated tracking issue #{issue_num} with error status.")
                else:
                    print(
                        f"[DRY RUN] Would update tracking issue #{issue_num} with"
                        f" error status."
                    )
                return 1
        else:
            # Patch release: tag branch head directly
            commit_sha = branch_sha
            latest_rc = None

        # Verify issue is in the right format by trying to prepare the update (for success case)
        metadata = {"status": "done", "tag": version, "commit": commit_sha[:8]}
        try:
            updated_body = update_task_in_body(
                body, "Tag Final", checked=True, metadata=metadata
            )
        except ValueError as e:
            print(f"Error: Tracking issue #{issue_num} is malformed: {e}")
            return 1

        # All pre-conditions met, perform modifications
        promote_source = (
            latest_rc
            if is_first_release
            else f"head of {branch_name} ({commit_sha[:8]})"
        )
        if args.dry_run:
            print(
                f"[DRY RUN] Pre-conditions passed successfully for promoting"
                f" {promote_source} to {version}."
            )
            print(f"[DRY RUN] Would tag commit {commit_sha[:8]} as {version}")
            print(f"[DRY RUN] Would push tag {version} to {args.remote}")
            print(f"[DRY RUN] Would update tracking issue #{issue_num} checklist")
            print(f"[DRY RUN] Would post comment to tracking issue #{issue_num}")
            return 0

        print(
            f"Promoting {promote_source} to final release {version} (commit"
            f" {commit_sha[:8]}) using tracking issue #{issue_num}..."
        )

        # Tag the specific commit without checkout, and push to remote
        self.git.tag(version, commit_sha)
        self.git.push(args.remote, version)

        if github_output := os.environ.get("GITHUB_OUTPUT"):
            with open(github_output, "a", encoding="utf-8") as f:
                f.write(f"version={version}\n")

        print(f"Updating tracking issue #{issue_num} checklist...")
        self.gh.update_issue_body(issue_num, updated_body)

        print(f"Posting comment to tracking issue #{issue_num}...")

        branch_url = f"{REPO_URL}/tree/{branch_name}"
        release_url = f"{REPO_URL}/releases/tag/{version}"
        bcr_entry_url = f"https://registry.bazel.build/modules/rules_python/{version}"
        bcr_query = (
            f'is:pr ("bazel-contrib/rules_python" in:title) ("@{version}" in:title)'
        )
        bcr_search_url = f"https://github.com/bazelbuild/bazel-central-registry/pulls?q={urllib.parse.quote(bcr_query)}"

        if run_id := os.environ.get("GITHUB_RUN_ID"):
            release_workflow_url = f"{REPO_URL}/actions/runs/{run_id}"
        else:
            release_workflow_url = f"{REPO_URL}/actions/workflows/release_promote.yaml"

        comment_body = f"""**New Release Tagged!** 🐍🌿

Version **{version}** has been successfully generated and tagged on branch [`{branch_name}`]({branch_url}).

- [Github Release {version}]({release_url})
- [BCR Entry {version}]({bcr_entry_url})
- [BCR PRs]({bcr_search_url})
- [Release workflow status]({release_workflow_url})"""
        self.gh.post_issue_comment(issue_num, comment_body)

        return 0

    @classmethod
    def add_parser(cls, subparsers):
        """Adds parser for promote-rc subcommand."""
        parser = subparsers.add_parser(
            "promote",
            help="Promote the latest RC to final release.",
        )
        parser.add_argument(
            "version",
            nargs="?",
            type=semver_type,
            help="The final version to release (e.g., 0.38.0).",
        )
        parser.add_argument(
            "--issue",
            type=int,
            help="The tracking issue number (optional).",
        )
        parser.add_argument(
            "--remote",
            type=str,
            required=True,
            help="The git remote to push the final tag to (required).",
        )
        parser.add_argument(
            "--dry-run",
            action=argparse.BooleanOptionalAction,
            default=True,
            help="Perform a dry run (default: True). Use --no-dry-run to actually execute.",
        )
        parser.set_defaults(command=cls.run_from_args)

    @classmethod
    def run_from_args(cls, args):
        """Instantiates and runs the command from parsed args."""
        git = Git(".")
        gh = GitHub()
        return cls(args, git, gh).run()

"""Subcommand to promote a release candidate to final release."""

import argparse
import urllib.parse

from tools.private.release.gh import GitHub
from tools.private.release.git import Git
from tools.private.release.release_issue import update_task_in_body
from tools.private.release.utils import (
    REPO_URL,
    determine_next_version,
    get_latest_rc_tag,
    semver_type,
)


class PromoteRc:
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
            version = determine_next_version()

        latest_rc = get_latest_rc_tag(version, remote=args.remote)
        if not latest_rc:
            print(f"Error: No release candidate tags found matching {version}-rc*")
            return 1

        # Verify final tag doesn't already exist
        if self.git.tag_exists(version):
            print(f"Error: Final tag {version} already exists.")
            return 1

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

        # Get commit SHA of the RC tag (which will be the same for the final tag)
        commit_sha = self.git.get_commit_sha(latest_rc)

        # Verify issue is in the right format by trying to prepare the update
        print(f"Verifying tracking issue #{issue_num} format...")
        body = self.gh.get_issue_body(issue_num)
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
                f"[DRY RUN] Pre-conditions passed successfully for promoting"
                f" {latest_rc} to {version}."
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

        # Tag the specific commit without checkout, and push to remote
        self.git.tag(version, commit_sha)
        self.git.push(args.remote, version)

        print(f"Updating tracking issue #{issue_num} checklist...")
        self.gh.update_issue_body(issue_num, updated_body)

        print(f"Posting comment to tracking issue #{issue_num}...")

        release_url = f"{REPO_URL}/releases/tag/{version}"
        bcr_query = (
            f'is:pr ("bazel-contrib/rules_python" in:title) ("@{version}" in:title)'
        )
        bcr_search_url = f"https://github.com/bazelbuild/bazel-central-registry/pulls?q={urllib.parse.quote(bcr_query)}"
        comment_body = (
            f"Version {version} has been tagged.\n\n"
            f"- **Release Page**: {release_url}\n"
            f"- **BCR PR Search**: [{bcr_query}]({bcr_search_url})"
        )
        self.gh.post_issue_comment(issue_num, comment_body)

        return 0

    @classmethod
    def add_parser(cls, subparsers):
        """Adds parser for promote-rc subcommand."""
        parser = subparsers.add_parser(
            "promote-rc",
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

"""Subcommand to prepare backport tracking issue and verify cherry-picks."""

import argparse
import datetime
import re
from dataclasses import dataclass

from tools.private.release import changelog_news
from tools.private.release.gh import BACKPORT_LABEL, GitHub
from tools.private.release.git import Git
from tools.private.release.utils import determine_next_version


@dataclass
class BackportMetadata:
    pr: str
    from_minor: str
    to_minor: str


def parse_backport_metadata(body) -> BackportMetadata:
    """Parses backport metadata from issue body."""
    pr_match = re.search(r"^\s*\*\s*PR:\s*(\S+)", body, re.MULTILINE | re.IGNORECASE)
    from_match = re.search(
        r"^\s*\*\s*From version:\s*(\S+)", body, re.MULTILINE | re.IGNORECASE
    )
    to_match = re.search(
        r"^\s*\*\s*To version:\s*(\S+)", body, re.MULTILINE | re.IGNORECASE
    )

    if not pr_match or not from_match or not to_match:
        raise ValueError(
            "Missing metadata in issue body. Need PR, From version, and To version."
        )

    return BackportMetadata(
        pr=pr_match.group(1),
        from_minor=from_match.group(1),
        to_minor=to_match.group(1),
    )


def get_target_branches(git, remote, from_minor, to_minor):
    """Identifies target release branches in the given range."""
    branches = git.get_remote_branches(remote)
    target_branches = []

    # Parse version strings to compare (only major and minor)
    from_v = [int(x) for x in from_minor.split(".")][:2]
    to_v = [int(x) for x in to_minor.split(".")][:2]

    for branch in branches:
        match = re.match(r"^release/(\d+)\.(\d+)$", branch)
        if match:
            major = int(match.group(1))
            minor = int(match.group(2))
            v = [major, minor]
            if v >= from_v and v <= to_v:
                target_branches.append(branch)

    # Sort branches by version
    target_branches.sort(key=lambda b: [int(x) for x in b.split("/")[1].split(".")])
    return target_branches


def get_latest_release_branch(git, remote):
    """Determines the latest release branch."""
    branches = git.get_remote_branches(remote)
    release_branches = []
    for branch in branches:
        match = re.match(r"^release/(\d+)\.(\d+)$", branch)
        if match:
            release_branches.append(branch)
    if not release_branches:
        return None
    release_branches.sort(key=lambda b: [int(x) for x in b.split("/")[1].split(".")])
    return release_branches[-1]


class BackportPrepare:
    """Class to prepare backport tracking issue and verify cherry-picks."""

    def __init__(self, args, git: Git, gh: GitHub):
        self.args = args
        self.git = git
        self.gh = gh

    def run(self) -> int:
        """Executes the backport-prepare subcommand."""
        args = self.args
        print("Fetching remote to verify release branches...")
        self.git.fetch(args.remote, tags=True, force=True)

        issue_num = args.issue

        if issue_num:
            # Triggered by comment, read from issue
            print(f"Reading metadata from issue #{issue_num}...")
            body = self.gh.get_issue_body(issue_num)
            try:
                metadata = parse_backport_metadata(body)
            except ValueError as e:
                e.add_note(f"Failed to parse backport metadata from issue #{issue_num}")
                raise
            pr_ref = metadata.pr
            from_minor = metadata.from_minor
            to_minor = metadata.to_minor
        else:
            # Triggered manually, use args
            pr_ref = args.pr
            from_minor = args.from_minor
            to_minor = args.to_minor

            if not pr_ref or not from_minor:
                raise ValueError(
                    "PR and From version are required if not running from an issue."
                )

            if not to_minor:
                latest_branch = get_latest_release_branch(self.git, args.remote)
                if not latest_branch:
                    raise RuntimeError(
                        "Could not determine latest release branch and --to-minor was not provided."
                    )
                to_minor = latest_branch.split("/")[1]
                print(f"Auto-determined latest minor version: {to_minor}")

        # Resolve PR to merge commit
        try:
            pr_num = self.gh.resolve_pr_number(pr_ref)
            print(f"Resolving PR #{pr_num} info...")
            pr_info = self.gh.get_pr_info(pr_num)
        except Exception as e:
            e.add_note(f"Failed to resolve PR info for {pr_ref}")
            raise

        if pr_info.get("state") != "MERGED":
            raise ValueError(
                f"PR #{pr_num} is not merged (state: {pr_info.get('state')})."
            )
        merge_commit = pr_info.get("mergeCommit")
        if not merge_commit or "oid" not in merge_commit:
            raise ValueError(f"PR #{pr_num} has no merge commit SHA.")
        pr_sha = merge_commit["oid"]
        print(f"Resolved PR #{pr_num} to merge commit {pr_sha[:8]}")

        target_branches = get_target_branches(
            self.git, args.remote, from_minor, to_minor
        )
        if not target_branches:
            raise ValueError(
                f"No release branches found in range {from_minor} to {to_minor}"
            )

        print(f"Identified target branches: {target_branches}")

        # Verify workspace is clean
        if self.git.status():
            raise RuntimeError("Workspace is dirty. Aborting.")

        current_branch = self.git.get_current_branch()
        verify_results = {}  # branch -> (success, reason)
        version_map = {}  # branch -> next_version

        try:
            for branch in target_branches:
                minor_ver = branch.split("/")[1]
                print(f"Verifying application on {branch}...")
                self.git.checkout(branch, track_remote=args.remote)

                # Determine next version
                next_version = determine_next_version(branch)
                version_map[branch] = next_version

                # Verify apply (cherry-pick + news)
                try:
                    self.git.cherry_pick(pr_sha)

                    # Try news update
                    try:
                        release_date = datetime.date.today().strftime("%Y-%m-%d")
                        changelog_news.update_changelog(next_version, release_date)
                        verify_results[branch] = (True, "Success")
                        print(f"Verification successful for {branch}")
                    except Exception as e:
                        verify_results[branch] = (
                            False,
                            f"Changelog update failed: {e}",
                        )
                        print(
                            f"Verification failed for {branch} (changelog update): {e}"
                        )
                except Exception as e:
                    verify_results[branch] = (False, f"Cherry-pick failed: {e}")
                    print(f"Verification failed for {branch} (cherry-pick): {e}")
                finally:
                    # Always abort/reset
                    try:
                        self.git.cherry_pick_abort()
                    except Exception:
                        pass
                    self.git.reset_hard(reset_to=f"{args.remote}/{branch}")
        finally:
            # Restore original branch
            if current_branch:
                self.git.checkout(current_branch)

        # Generate issue content
        body_lines = [
            f"* PR: #{pr_num}",
            f"* From version: {from_minor}",
            f"* To version: {to_minor}",
            "",
            "## Tasks",
            "",
        ]

        # Add Verify tasks
        for branch in target_branches:
            minor_ver = branch.split("/")[1]
            success, reason = verify_results[branch]
            if success:
                body_lines.append(f"- [x] Verify apply {minor_ver} | status=success")
            else:
                status = "failed-conflict"
                if "Changelog" in reason:
                    status = "failed-changelog"
                body_lines.append(f"- [ ] Verify apply {minor_ver} | status={status}")

        # Add Release tasks
        for branch in target_branches:
            next_version = version_map[branch]
            body_lines.append(f"- [ ] Track Release {next_version}")

        new_body = "\n".join(body_lines)

        if issue_num:
            if args.dry_run:
                print(
                    f"[DRY RUN] Would update issue #{issue_num} with body:\n{new_body}"
                )
            else:
                self.gh.update_issue_body(issue_num, new_body)
                print(f"Successfully updated issue #{issue_num}")
        else:
            title = f"Backport: #{pr_num}"
            if args.dry_run:
                print(
                    f"[DRY RUN] Would create issue with title '{title}' and body:\n{new_body}"
                )
            else:
                new_issue_num = self.gh.create_issue(
                    title, new_body, labels=[BACKPORT_LABEL]
                )
                print(f"Created backport tracking issue #{new_issue_num}")

        return 0

    @classmethod
    def add_parser(cls, subparsers):
        """Adds parser for backport-prepare subcommand."""
        parser = subparsers.add_parser(
            "backport-prepare",
            help="Prepare backport tracking issue and verify cherry-picks.",
        )
        parser.add_argument(
            "--issue",
            type=int,
            help="The backport tracking issue number (if running from an existing issue).",
        )
        parser.add_argument(
            "--pr",
            type=str,
            help="PR reference to backport (required if not running from issue).",
        )
        parser.add_argument(
            "--from-minor",
            type=str,
            help="Oldest minor version to target (inclusive) (e.g. 1.7) (required if not running from issue).",
        )
        parser.add_argument(
            "--to-minor",
            type=str,
            help="Newest minor version to target (inclusive) (optional, defaults to latest).",
        )
        parser.add_argument(
            "--remote",
            type=str,
            default="origin",
            help="The git remote (default: origin).",
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

"""Subcommand to handle PR merge event by processing backports."""

import argparse
import re

from tools.private.release.gh import GitHub
from tools.private.release.git import Git
from tools.private.release.process_backports import ProcessBackports
from tools.private.release.release_issue import parse_backports


class OnPrMerged:
    """Class to handle PR merge event."""

    def __init__(self, args, git: Git, gh: GitHub):
        self.args = args
        self.git = git
        self.gh = gh

    def run(self) -> int:
        """Executes the on-pr-merged subcommand."""
        args = self.args
        pr_num = args.pr
        pr_ref = f"#{pr_num}"

        print(f"Verifying PR {pr_ref} has backport comment...")
        try:
            comments = self.gh.get_pr_comments(pr_num)
            has_comment = any(
                re.match(
                    r"^\s*/backport(\s|$)",
                    comment.get("body") or "",
                    re.IGNORECASE,
                )
                for comment in comments
            )
            if not has_comment:
                print(f"PR {pr_ref} does not have a /backport comment. Skipping.")
                return 1
        except Exception as e:
            print(f"Error checking PR comments: {e}")
            return 1

        print(f"Searching for active release tracking issue containing PR {pr_ref}...")
        open_issues = self.gh.get_open_tracking_issues()
        if not open_issues:
            print("No open release tracking issues found.")
            return 1

        found_issue = None
        for issue in open_issues:
            issue_num = issue["number"]
            body = self.gh.get_issue_body(issue_num)
            backports = parse_backports(body)

            if any(item.pr_ref == pr_ref for item in backports):
                if found_issue:
                    print(
                        f"Error: PR {pr_ref} found in multiple open release"
                        f" tracking issues: #{found_issue} and #{issue_num}"
                    )
                    return 1
                found_issue = issue_num

        if not found_issue:
            print(f"PR {pr_ref} not found in any active release tracking issue.")
            return 1

        print(f"Found PR {pr_ref} in tracking issue #{found_issue}")

        # Now run ProcessBackports for this issue
        process_args = argparse.Namespace(
            issue=found_issue,
            remote=args.remote,
            add=None,
            triggering_comment=None,
            dry_run=args.dry_run,
        )
        print(f"Processing backports for issue #{found_issue}...")
        return ProcessBackports(process_args, self.git, self.gh).run()

    @classmethod
    def add_parser(cls, subparsers):
        """Adds parser for on-pr-merged subcommand."""
        parser = subparsers.add_parser(
            "on-pr-merged",
            help="Handle PR merge event by processing backports.",
        )
        parser.add_argument(
            "pr",
            type=int,
            help="PR number that was merged.",
        )
        parser.add_argument(
            "--remote",
            type=str,
            required=True,
            help="The git remote to push changes to (required).",
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

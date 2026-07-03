"""Subcommand to add and process backports."""

import argparse

from tools.private.release.gh import GitHub
from tools.private.release.git import Git
from tools.private.release.process_backports import ProcessBackports
from tools.private.release.release_issue import add_backports_to_body


class AddBackports:
    """Class to add and process backports."""

    def __init__(self, args, git: Git, gh: GitHub):
        self.args = args
        self.git = git
        self.gh = gh

    def run(self) -> int:
        """Executes the add-backports subcommand."""
        args = self.args
        print(f"Adding backports {args.prs} to tracking issue #{args.issue}...")
        body = self.gh.get_issue_body(args.issue)

        try:
            updated_body = add_backports_to_body(body, args.prs)
        except ValueError as e:
            print(f"Error: {e}")
            return 1

        if updated_body != body:
            if not args.dry_run:
                self.gh.update_issue_body(args.issue, updated_body)
                print("Successfully updated tracking issue checklist.")
                # We need to get the updated body again because the process-backports
                # job will read it from GH.
                # Actually, ProcessBackports(args) will fetch it again in its run()
                # so we don't need to pass it.
            else:
                print(
                    "[DRY RUN] Would update tracking issue checklist with new"
                    " backports."
                )
        else:
            print("No new backports to add to the checklist.")

        # Now process them
        processor = ProcessBackports(args, self.git, self.gh)
        return processor.run()

    @classmethod
    def add_parser(cls, subparsers):
        """Adds parser for add-backports subcommand."""
        parser = subparsers.add_parser(
            "add-backports",
            help="Add pending backports to the tracking issue and process them.",
        )
        parser.add_argument(
            "prs",
            nargs="+",
            type=int,
            help="PR numbers to backport (space-separated).",
        )
        parser.add_argument(
            "--issue",
            type=int,
            required=True,
            help="The tracking issue number (required).",
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

"""Subcommand to find the release tracking issue containing a specific PR in its backports."""

import os
import sys

from tools.private.release.gh import GitHub
from tools.private.release.release_issue import parse_backports


class FindReleaseIssue:
    """Class to find the release tracking issue for a PR."""

    def __init__(self, args, gh: GitHub):
        self.args = args
        self.gh = gh

    def run(self) -> int:
        """Executes the find-release-issue subcommand."""
        args = self.args
        pr_ref = f"#{args.pr}"

        print(f"Searching for active release tracking issue containing PR {pr_ref}...")
        try:
            open_issues = self.gh.get_open_tracking_issues()
            if not open_issues:
                print("No open release tracking issues found.")
                return 1

            found_issue = None
            for issue in open_issues:
                issue_num = issue["number"]
                body = self.gh.get_issue_body(issue_num)
                backports = parse_backports(body)

                # Check if pr_ref is in backports
                if any(item.pr_ref == pr_ref for item in backports):
                    if found_issue:
                        print(
                            f"Error: PR {pr_ref} found in multiple open release"
                            f" tracking issues: #{found_issue} and #{issue_num}"
                        )
                        return 1
                    found_issue = issue_num

            if found_issue:
                print(f"Found PR {pr_ref} in tracking issue #{found_issue}")
                github_output = os.environ.get("GITHUB_OUTPUT")
                if github_output:
                    try:
                        with open(github_output, "a") as f:
                            f.write(f"issue={found_issue}\n")
                        print(f"Wrote issue={found_issue} to GITHUB_OUTPUT")
                    except Exception as e:
                        print(
                            f"Failed to write to GITHUB_OUTPUT: {e}",
                            file=sys.stderr,
                        )
                        return 1
                else:
                    print(f"issue={found_issue}")
                return 0
            else:
                print(f"PR {pr_ref} not found in any active release tracking issue.")
                return 1

        except Exception as e:
            print(f"Error: {e}")
            return 1

    @classmethod
    def add_parser(cls, subparsers):
        """Adds parser for find-release-issue subcommand."""
        parser = subparsers.add_parser(
            "find-release-issue",
            help=(
                "Find the release tracking issue containing a specific PR in"
                " its backports."
            ),
        )
        parser.add_argument(
            "pr",
            type=int,
            help="PR number to search for.",
        )
        parser.set_defaults(command=cls.run_from_args)

    @classmethod
    def run_from_args(cls, args):
        """Instantiates and runs the command from parsed args."""
        gh = GitHub()
        return cls(args, gh).run()

"""Subcommand to create a release tracking issue."""

from dev.release.gh import GitHub, format_complete_issue_warning
from dev.release.release_issue import load_release_tracking_template
from dev.release.utils import determine_next_version, semver_type


class CreateReleaseIssue:
    """Class to create a release tracking issue."""

    def __init__(self, args, gh: GitHub):
        self.args = args
        self.gh = gh

    def run(self) -> int:
        """Executes the create-release-issue subcommand."""
        version = self.args.version
        if version is None:
            version = determine_next_version()

        # Concurrency check: only a release still in progress blocks a new one.
        active_issues, complete_issues = self.gh.partition_open_tracking_issues()
        for issue in complete_issues:
            print(f"::warning::{format_complete_issue_warning(issue)}")
        if active_issues:
            print("Error: A release is already in progress. Active tracking issues:")
            for issue in active_issues:
                print(f"- {issue['title']}: {issue['url']}")
            return 1

        template_content = load_release_tracking_template(version=version)

        issue_num = self.gh.create_release_tracking_issue(version, template_content)
        print(f"Created tracking issue #{issue_num} for v{version}")
        return 0

    @classmethod
    def add_parser(cls, subparsers):
        """Adds parser for create-release-issue subcommand."""
        parser = subparsers.add_parser(
            "create-release-issue",
            help="Search for open releases and create a new tracking issue.",
        )
        parser.add_argument(
            "--version",
            type=semver_type,
            help="The release version (e.g., 0.38.0). If not provided, determined automatically.",
        )
        parser.set_defaults(command=cls.run_from_args)

    @classmethod
    def run_from_args(cls, args):
        """Instantiates and runs the command from parsed args."""
        gh = GitHub()
        return cls(args, gh).run()

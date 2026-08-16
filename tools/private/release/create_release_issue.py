"""Subcommand to create a release tracking issue."""

from tools.private.release.gh import GitHub
from tools.private.release.release_issue import load_release_tracking_template
from tools.private.release.utils import determine_next_version, semver_type


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

        # Concurrency check
        open_issues = self.gh.get_open_tracking_issues()
        if open_issues:
            print("Error: A release is already in progress. Active tracking issues:")
            for issue in open_issues:
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

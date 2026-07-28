"""Subcommand to determine the next version."""

from tools.private.release.utils import determine_next_version


class DetermineNextVersion:
    """Class to determine the next version."""

    def __init__(self, args, git=None, gh=None):
        self.args = args

    def run(self) -> int:
        """Executes the determine-next-version subcommand."""
        version = determine_next_version()
        print(version)
        return 0

    @classmethod
    def add_parser(cls, subparsers):
        """Adds parser for determine-next-version subcommand."""
        parser = subparsers.add_parser(
            "determine-next-version",
            help="Determine the next version and print it, without making any changes.",
        )
        parser.set_defaults(command=cls.run_from_args)

    @classmethod
    def run_from_args(cls, args):
        """Instantiates and runs the command from parsed args."""
        return cls(args).run()

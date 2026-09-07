"""A tool to perform release steps."""

import argparse
import logging
import os
import sys

from dev.release.add_backports import AddBackports
from dev.release.backport_create_releases import BackportCreateReleases
from dev.release.backport_prepare import BackportPrepare
from dev.release.complete_prepare import CompletePrepare
from dev.release.complete_sync_changelog import CompleteSyncChangelog
from dev.release.create_rc import CreateRc
from dev.release.create_release_branch import CreateReleaseBranch
from dev.release.create_release_issue import CreateReleaseIssue
from dev.release.determine_next_version import DetermineNextVersion
from dev.release.on_pr_merged import OnPrMerged
from dev.release.prepare import Prepare
from dev.release.process_backports import ProcessBackports
from dev.release.process_news import ProcessNews
from dev.release.promote import Promote
from dev.release.sync_changelog import SyncChangelog
from dev.release.utils import format_exception

cmds = [
    DetermineNextVersion,
    CreateReleaseIssue,
    Prepare,
    CompletePrepare,
    CompleteSyncChangelog,
    CreateReleaseBranch,
    AddBackports,
    ProcessBackports,
    ProcessNews,
    SyncChangelog,
    OnPrMerged,
    CreateRc,
    Promote,
    BackportPrepare,
    BackportCreateReleases,
]


def create_parser():
    """Creates the argument parser with subcommands."""
    parser = argparse.ArgumentParser(
        description="Automate release steps for rules_python."
    )

    subparsers = parser.add_subparsers(
        dest="command", required=True, help="Subcommands"
    )

    for cmd in cmds:
        cmd.add_parser(subparsers)

    return parser


class GitHubActionsLogHandler(logging.Handler):
    """Outputs GitHub Actions workflow command annotations for log records."""

    def emit(self, record: logging.LogRecord) -> None:
        if record.levelno >= logging.ERROR:
            prefix = "::error::"
        elif record.levelno >= logging.WARNING:
            prefix = "::warning::"
        elif record.levelno >= logging.INFO:
            prefix = "::notice::"
        else:
            return
        try:
            msg = record.getMessage()
            print(f"{prefix}{msg}", file=sys.stdout, flush=True)
        except Exception:
            self.handleError(record)


def main():
    logging.basicConfig(
        format="%(levelname)s:%(filename)s:%(lineno)d: %(message)s",
        level=logging.INFO,
        stream=sys.stderr,
    )
    logging.getLogger().addHandler(GitHubActionsLogHandler())
    print(f"sys.argv: {sys.argv}")
    if "BUILD_WORKSPACE_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKSPACE_DIRECTORY"])

    parser = create_parser()
    args = parser.parse_args()

    exit_code = 1
    try:
        # args.command is the run_from_args classmethod of the selected command
        exit_code = args.command(args)
    except Exception as e:
        sys.stdout.flush()
        print(f"Fatal error: {format_exception(e)}", file=sys.stderr)
        sys.exit(1)

    sys.exit(exit_code if exit_code is not None else 0)


if __name__ == "__main__":
    main()

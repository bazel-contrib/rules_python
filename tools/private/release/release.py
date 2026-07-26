"""A tool to perform release steps."""

import argparse
import os
import sys

from tools.private.release.add_backports import AddBackports
from tools.private.release.backport_create_releases import BackportCreateReleases
from tools.private.release.backport_prepare import BackportPrepare
from tools.private.release.complete_prepare import CompletePrepare
from tools.private.release.complete_sync_changelog import CompleteSyncChangelog
from tools.private.release.create_rc import CreateRc
from tools.private.release.create_release_branch import CreateReleaseBranch
from tools.private.release.create_release_issue import CreateReleaseIssue
from tools.private.release.determine_next_version import DetermineNextVersion
from tools.private.release.on_pr_merged import OnPrMerged
from tools.private.release.prepare import Prepare
from tools.private.release.process_backports import ProcessBackports
from tools.private.release.promote import Promote

cmds = [
    DetermineNextVersion,
    CreateReleaseIssue,
    Prepare,
    CompletePrepare,
    CompleteSyncChangelog,
    CreateReleaseBranch,
    AddBackports,
    ProcessBackports,
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


def main():
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
        print(f"Fatal error: {e}", file=sys.stderr)
        if hasattr(e, "__notes__"):
            for note in e.__notes__:
                print(note, file=sys.stderr)
        sys.exit(1)

    sys.exit(exit_code if exit_code is not None else 0)


if __name__ == "__main__":
    main()

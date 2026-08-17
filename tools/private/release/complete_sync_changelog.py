"""Subcommand to mark sync changelog tasks as complete."""

import logging
import re

from tools.private.release.gh import GitHub, get_github_event_pr_number
from tools.private.release.release_issue import (
    parse_checklist_state,
    update_task_in_body,
)

logger = logging.getLogger(__name__)


class CompleteSyncChangelog:
    """Class to mark sync changelog tasks as complete."""

    def __init__(self, args, gh: GitHub):
        self.args = args
        self.gh = gh

    def run(self) -> int:
        """Executes the complete-sync-changelog subcommand."""
        args = self.args
        pr_num = args.pr or get_github_event_pr_number()
        if not pr_num:
            logger.error(
                "No PR specified and could not extract PR number from GITHUB_EVENT_PATH."
            )
            return 1

        logger.info("Completing sync changelog for PR #%d...", pr_num)

        pr_info = self.gh.get_pr_info(pr_num)
        if not pr_info or pr_info.get("state") != "MERGED":
            state = pr_info.get("state", "UNKNOWN")
            logger.error("PR #%d is not merged yet (state: %s).", pr_num, state)
            return 1

        # Resolve issue number from PR body using Release-Tracking-Issue: #<issue>
        pr_body = pr_info.get("body") or ""
        match = re.search(r"Release-Tracking-Issue:\s*#(\d+)", pr_body)
        if not match:
            logger.error(
                "Could not find 'Release-Tracking-Issue: #<issue>' in PR #%d body: %s",
                pr_num,
                pr_body,
            )
            return 1

        issue_num = int(match.group(1))
        logger.info("Resolved tracking issue #%d from PR #%d body.", issue_num, pr_num)

        commit_sha = pr_info["mergeCommit"]["oid"]
        short_commit = commit_sha[:8]
        logger.info(
            "PR #%d merged at commit %s. Updating tracking issue...",
            pr_num,
            commit_sha,
        )

        # Update checklist: mark all Sync Changelog tasks pointing to this PR as done
        body = self.gh.get_issue_body(issue_num)
        state = parse_checklist_state(body)
        sync_changelogs = state.get("sync_changelogs", {})

        updated_any = False
        for target_pr_num, task in sync_changelogs.items():
            # Check if this task points to our merged PR
            task_pr = task.metadata.get("pr")
            if task_pr == f"#{pr_num}":
                logger.info("Marking task '%s' as complete...", task.name)
                metadata = {
                    "status": "done",
                    "pr": f"#{pr_num}",
                    "commit": short_commit,
                }
                body = update_task_in_body(
                    body, task.name, checked=True, metadata=metadata
                )
                updated_any = True

        if not updated_any:
            logger.warning("No 'Sync Changelog' tasks found pointing to PR #%d", pr_num)
            return 0

        self.gh.update_issue_body(issue_num, body)
        logger.info("Sync changelog tasks marked complete successfully!")
        return 0

    @classmethod
    def add_parser(cls, subparsers):
        """Adds parser for complete-sync-changelog subcommand."""
        parser = subparsers.add_parser(
            "complete-sync-changelog",
            help="Mark the Sync Changelog tasks as complete in the tracking issue.",
        )
        parser.add_argument(
            "--pr",
            type=int,
            help="The merged sync changelog PR number (optional; extracted from GITHUB_EVENT_PATH if omitted).",
        )
        parser.set_defaults(command=cls.run_from_args)

    @classmethod
    def run_from_args(cls, args):
        """Instantiates and runs the command from parsed args."""
        gh = GitHub()
        return cls(args, gh).run()

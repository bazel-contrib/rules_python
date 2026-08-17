"""Subcommand to create sync PR to main for backports in a release."""

import argparse
import hashlib
import logging
import traceback

from tools.private.release.gh import (
    GH_REACTION_THUMBS_DOWN,
    GitHub,
    GitHubInterface,
)
from tools.private.release.git import Git
from tools.private.release.process_news import ProcessNews
from tools.private.release.release_issue import (
    RELEASE_TITLE_RE,
    parse_checklist_state,
    update_task_in_body,
)
from tools.private.release.utils import format_exception, parse_pr_list

logger = logging.getLogger(__name__)


class SyncChangelog:
    """Class to sync changelog to main for backports in a release."""

    def __init__(self, args, git: Git, gh: GitHubInterface):
        self.args = args
        self.git = git
        self.gh = gh

    def run(self) -> int:
        """Executes the sync-changelog subcommand."""
        args = self.args
        exit_code = 0
        try:
            exit_code = self._run_internal()
        except Exception as e:
            logger.error("Unexpected error: %s", e)
            traceback.print_exc()
            exit_code = 1

        if exit_code != 0 and args.triggering_comment:
            logger.info(
                "Reacting with thumbs-down to comment %s...",
                args.triggering_comment,
            )
            try:
                self.gh.add_comment_reaction(
                    args.triggering_comment, GH_REACTION_THUMBS_DOWN
                )
            except Exception as e:
                logger.error("Failed to add reaction to comment: %s", e)

        return exit_code

    def _run_internal(self) -> int:
        """Internal implementation of sync-changelog."""
        args = self.args
        issue_num = args.issue
        if not issue_num:
            logger.info(
                "No issue specified. Auto-discovering open release tracking issue..."
            )
            open_issues = self.gh.get_open_tracking_issues()
            if len(open_issues) > 1:
                logger.error(
                    "Multiple open release tracking issues found: %s",
                    [f"#{i['number']}" for i in open_issues],
                )
                return 1
            elif len(open_issues) == 1:
                issue_num = open_issues[0]["number"]
                logger.info("Discovered release tracking issue #%d", issue_num)
            else:
                logger.error("No open release tracking issues found.")
                return 1

        body = self.gh.get_issue_body(issue_num)
        issue_title = self.gh.get_issue_title(issue_num)
        version_match = RELEASE_TITLE_RE.search(issue_title)
        if not version_match:
            logger.error("Could not parse version from issue title: %s", issue_title)
            return 1

        version = version_match.group(1)

        if args.prs:
            pending_prs = []
            for pr_ref in args.prs:
                try:
                    pr_num = self.gh.resolve_pr_number(pr_ref)
                    pending_prs.append(pr_num)
                except Exception as e:
                    logger.error(
                        "Failed to resolve PR reference '%s': %s",
                        pr_ref,
                        format_exception(e),
                    )
                    return 1
        else:
            state = parse_checklist_state(body)
            sync_tasks = state.get("sync_changelogs", {})
            pending_prs = [
                pr_num
                for pr_num, task in sync_tasks.items()
                if not task.checked
                and task.status != "done"
                and not (task.status or "").startswith("error-")
            ]

        if not pending_prs:
            logger.info("No pending sync changelog tasks found.")
            return 0

        logger.info(
            "Found %d pending sync changelog tasks to process: %s",
            len(pending_prs),
            pending_prs,
        )

        if self.git.status():
            logger.error(
                "Git workspace is dirty. Please commit or stash changes"
                " before running sync-changelog."
            )
            return 1

        sorted_prs = sorted(pending_prs)
        prs_str = ",".join(str(n) for n in sorted_prs)
        prs_hash = hashlib.sha256(prs_str.encode()).hexdigest()[:7]

        main_branch = "main"
        backport_branch = f"prepare-{version}-backports-{prs_hash}"

        self.git.fetch(args.remote, refspec=main_branch)
        self.git.checkout(main_branch, track_remote=args.remote)
        main_start_sha = self.git.get_commit_sha("HEAD")

        try:
            if args.dry_run:
                logger.info(
                    "[DRY RUN] Would create and checkout branch %s from %s",
                    backport_branch,
                    main_branch,
                )
            else:
                if self.git.branch_exists(backport_branch):
                    self.git.checkout(backport_branch)
                    self.git.reset_hard(reset_to=main_branch)
                else:
                    self.git.checkout(backport_branch, create_branch=True)

            # Run ProcessNews to process news files and version markers
            process_news_args = argparse.Namespace(
                version=version,
                targets=[str(pr) for pr in sorted_prs],
            )
            process_news_runner = ProcessNews(process_news_args, gh=self.gh)
            ret = process_news_runner.run()
            if ret != 0:
                logger.error("ProcessNews failed for targets: %s", sorted_prs)
                return 1

            if not self.git.status():
                logger.info("No changes to sync after running process-news.")
                return 0

            if args.dry_run:
                logger.info(
                    "[DRY RUN] Would commit: 'chore(release): sync changelog"
                    " for v%s backports'",
                    version,
                )
                logger.info(
                    "[DRY RUN] Would push %s to %s",
                    backport_branch,
                    args.remote,
                )
                logger.info(
                    "[DRY RUN] Would create PR to %s with label 'type: sync-changelog'",
                    main_branch,
                )
                logger.info(
                    "[DRY RUN] Would update tracking issue #%s checklist tasks"
                    " 'Sync Changelog #<pr>' to PENDING",
                    issue_num,
                )
                logger.info("[DRY RUN] Diff of changes:\n%s", self.git.status())
            else:
                self.git.add_modified_and_deleted()
                self.git.commit(
                    f"chore(release): sync changelog for v{version} backports"
                )
                self.git.push(
                    args.remote, backport_branch, set_upstream=True, force=True
                )

                pr_title = f"chore(release): sync changelog for v{version} backports"
                pr_body_lines = [
                    "Updates CHANGELOG.md and removes news files for backports:",
                ]
                for pr_num in sorted_prs:
                    pr_body_lines.append(f"- #{pr_num}")

                pr_body_lines.append("")
                pr_body_lines.append(f"Work towards #{issue_num}")
                pr_body_lines.append(f"Release-Tracking-Issue: #{issue_num}")
                pr_body = "\n".join(pr_body_lines)

                logger.info("Creating PR to %s...", main_branch)
                pr_url = self.gh.create_pr(
                    title=pr_title,
                    body=pr_body,
                    base=main_branch,
                    labels=["type: sync-changelog"],
                )
                logger.info("Created PR: %s", pr_url)

                try:
                    pr_num = int(pr_url.split("/")[-1])
                    logger.info("Enabling auto-merge for PR #%s...", pr_num)
                    self.gh.enable_auto_merge(pr_num)

                    logger.info(
                        "Updating tracking issue #%s checklist with"
                        " Sync Changelog tasks...",
                        issue_num,
                    )
                    issue_body = self.gh.get_issue_body(issue_num)
                    for pr in sorted_prs:
                        task_name = f"Sync Changelog #{pr}"
                        metadata = {"status": "pending", "pr": f"#{pr_num}"}
                        issue_body = update_task_in_body(
                            issue_body,
                            task_name,
                            checked=False,
                            metadata=metadata,
                        )
                    self.gh.update_issue_body(issue_num, issue_body)
                except Exception as e:
                    logger.warning(
                        "Failed to update tracking issue or enable auto-merge: %s",
                        format_exception(e),
                    )
        finally:
            if args.dry_run:
                logger.info(
                    "[DRY RUN] Resetting branch %s to %s after changelog sync dry run",
                    main_branch,
                    main_start_sha,
                )
                self.git.reset_hard(reset_to=main_start_sha)
            self.git.checkout(main_branch)

        return 0

    @classmethod
    def add_parser(cls, subparsers):
        """Adds parser for sync-changelog subcommand."""
        parser = subparsers.add_parser(
            "sync-changelog",
            help="Create a sync PR to main for backports in a release.",
        )
        parser.add_argument(
            "--issue",
            type=int,
            help="The tracking issue number (optional; auto-discovered if omitted).",
        )
        parser.add_argument(
            "--remote",
            type=str,
            required=True,
            help="The git remote to push changes to (required).",
        )
        parser.add_argument(
            "--prs",
            type=parse_pr_list,
            help=(
                "PR references (numbers, #numbers, or URLs, comma/space"
                " separated) to sync (optional)."
            ),
        )
        parser.add_argument(
            "--triggering-comment",
            type=int,
            help="The ID of the comment that triggered this run (optional).",
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

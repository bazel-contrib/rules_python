"""Subcommand to process pending backports."""

import argparse
import datetime
import logging
import traceback
from dataclasses import dataclass
from typing import Any

from tools.private.release import changelog_news
from tools.private.release.gh import GH_REACTION_THUMBS_DOWN, GitHub
from tools.private.release.git import Git
from tools.private.release.release_issue import (
    RELEASE_TITLE_RE,
    add_backports_to_body,
    add_rc_task_to_body,
    add_sync_changelog_task_to_body,
    parse_backports,
    parse_checklist_state,
    update_task_in_body,
)
from tools.private.release.utils import (
    format_exception,
    get_latest_rc_tag,
    parse_pr_list,
    replace_version_next,
)

logger = logging.getLogger(__name__)


@dataclass
class CherryPickAndUpdatePrsResult:
    # List of PR references that failed to cherry-pick.
    failed_prs: list[str]
    # The updated checklist body for the release tracking issue.
    body: str


class ProcessBackports:
    """Class to process pending backports."""

    def __init__(self, args, git: Git, gh: GitHub):
        self.args = args
        self.git = git
        self.gh = gh

    def _process_pr_commit_infos(
        self, pr_commit_infos, body, issue, dry_run
    ) -> tuple[list[str], dict[str, Any], list[str], list[str], str]:
        shas = []
        sha_to_item = {}
        failed_prs = []
        ignored_prs = []
        for item in pr_commit_infos:
            if item.commit:
                sha = item.commit
                sha_to_item[sha] = item
                shas.append(sha)
            elif item.status in ("open-pr", "draft-pr"):
                logger.info("PR %s is open or draft. Ignoring.", item.pr_ref)
                ignored_prs.append(item.pr_ref)
            else:
                failed_prs.append(item.pr_ref)
                status_to_set = item.status or "error-unmerged-pr"
                if dry_run:
                    logger.info(
                        "[DRY RUN] Would update tracking issue checklist for"
                        " unresolved PR %s to status=%s",
                        item.pr_ref,
                        status_to_set,
                    )
                else:
                    logger.info(
                        "Updating tracking issue checklist for unresolved PR %s...",
                        item.pr_ref,
                    )
                    try:
                        body = update_task_in_body(
                            body,
                            item.pr_ref,
                            checked=False,
                            metadata={"status": status_to_set},
                        )
                        self.gh.update_issue_body(issue, body)
                    except Exception as e:
                        logger.error(
                            "Failed to update tracking issue for unresolved PR %s: %s",
                            item.pr_ref,
                            format_exception(e),
                        )
        return shas, sha_to_item, failed_prs, ignored_prs, body

    def _cherry_pick_and_update_prs(
        self,
        sorted_shas,
        sha_to_item,
        body,
        issue,
        remote,
        dry_run,
        version,
        branch_name,
        next_rc_suffix,
    ) -> CherryPickAndUpdatePrsResult:
        failed_prs = []
        for sha in sorted_shas:
            item = sha_to_item[sha]
            logger.info("Cherry-picking %s / %s...", item.pr_ref, sha)
            try:
                self.git.cherry_pick(sha)

                # Replace version markers FIRST
                logger.info("Replacing version markers for PR %s...", item.pr_ref)
                replace_version_next(version)

                # Perform news processing (merging news/ files into the changelog)
                logger.info(
                    "Merging news fragments into changelog for PR %s...",
                    item.pr_ref,
                )
                release_date = datetime.date.today().strftime("%Y-%m-%d")
                changelog_news.update_changelog(version, release_date)

                # Stage changelog changes, news/ deletions, and version placeholder updates
                self.git.add_modified_and_deleted()

                # Amend cherry-pick commit to include news merging and deletions,
                # and reference the release tracking issue.
                logger.info("Amending cherry-pick commit for PR %s...", item.pr_ref)
                current_msg = self.git.get_commit_message("HEAD")
                new_msg = f"{current_msg.strip()}\n\nWork towards #{issue}"
                self.git.commit(new_msg, amend=True)

                if not dry_run:
                    # Push amended commit
                    self.git.push(remote, branch_name)

                    new_sha = self.git.get_commit_sha("HEAD", short=True)
                    metadata = {
                        "status": "done",
                        "rc": next_rc_suffix,
                        "commit": new_sha,
                    }
                    logger.info(
                        "Updating tracking issue checklist for PR %s...",
                        item.pr_ref,
                    )
                    try:
                        body = update_task_in_body(
                            body, item.pr_ref, checked=True, metadata=metadata
                        )
                        self.gh.update_issue_body(issue, body)
                    except Exception as e:
                        logger.error(
                            "Failed to update tracking issue for PR %s: %s",
                            item.pr_ref,
                            format_exception(e),
                        )
                    logger.info(
                        "Success: backported %s / %s to %s",
                        item.pr_ref,
                        sha,
                        branch_name,
                    )
                else:
                    logger.info(
                        "[DRY RUN] Success: %s / %s can be backported without error.",
                        item.pr_ref,
                        sha,
                    )
                    logger.info(
                        "[DRY RUN] Would update tracking issue checklist for"
                        " PR %s to status=done",
                        item.pr_ref,
                    )
            except Exception as e:
                logger.error(
                    "Conflict or error on %s: %s. Aborting.",
                    sha,
                    format_exception(e),
                )
                try:
                    self.git.cherry_pick_abort()
                except Exception:
                    pass
                failed_prs.append(item.pr_ref)

                if dry_run:
                    logger.info(
                        "[DRY RUN] Would update tracking issue checklist for"
                        " failed PR %s to status=error-merge-conflict",
                        item.pr_ref,
                    )
                else:
                    logger.info(
                        "Updating tracking issue checklist for failed PR %s...",
                        item.pr_ref,
                    )
                    try:
                        body = update_task_in_body(
                            body,
                            item.pr_ref,
                            checked=False,
                            metadata={"status": "error-merge-conflict"},
                        )
                        self.gh.update_issue_body(issue, body)
                        logger.info(
                            "Updated back port of %s to"
                            " status=error-merge-conflict (unchecked)",
                            item.pr_ref,
                        )
                    except Exception as e:
                        logger.error(
                            "Failed to update tracking issue for failed PR %s: %s",
                            item.pr_ref,
                            format_exception(e),
                        )
        return CherryPickAndUpdatePrsResult(
            failed_prs=failed_prs,
            body=body,
        )

    def run(self) -> int:
        """Executes the process-backports subcommand."""
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
        """Internal implementation of process-backports."""
        args = self.args
        body = self.gh.get_issue_body(args.issue)

        if args.add:
            items_to_add: list[dict[str, Any]] = []
            for pr_ref in args.add:
                try:
                    pr_num = self.gh.resolve_pr_number(pr_ref)
                    items_to_add.append({"ref": f"#{pr_num}"})
                except Exception as e:
                    logger.warning(
                        "PR ref '%s' is invalid: %s",
                        pr_ref,
                        format_exception(e),
                    )
                    items_to_add.append(
                        {
                            "ref": pr_ref,
                            "metadata": {"status": "error-invalid-pr"},
                        }
                    )

            logger.info(
                "Adding backports %s to tracking issue #%s...",
                items_to_add,
                args.issue,
            )
            try:
                body = add_backports_to_body(body, items_to_add)
                for item in items_to_add:
                    if (
                        "metadata" in item
                        and item["metadata"].get("status") == "error-invalid-pr"
                    ):
                        continue
                    pr_num = int(item["ref"].lstrip("#"))
                    body = add_sync_changelog_task_to_body(body, pr_num)
                state = parse_checklist_state(body)
                rc_tags = state.get("rc_tags", {})
                has_pending_rc = any(
                    not task.checked and task.status != "done"
                    for task in rc_tags.values()
                )
                next_rc_num = max(rc_tags.keys()) + 1 if rc_tags else 0
                if not has_pending_rc:
                    logger.info(
                        "No pending RC task found. Adding 'Tag RC%s' to checklist...",
                        next_rc_num,
                    )
                    body = add_rc_task_to_body(body, next_rc_num)
            except ValueError as e:
                logger.error("Error: %s", e)
                return 1

            if not args.dry_run:
                self.gh.update_issue_body(args.issue, body)
                logger.info("Successfully updated tracking issue checklist.")
            else:
                logger.info(
                    "[DRY RUN] Would update tracking issue checklist with new"
                    " backports."
                )
                if not has_pending_rc:
                    logger.info(
                        "[DRY RUN] Would add 'Tag RC%s' to checklist.",
                        next_rc_num,
                    )

        items = parse_backports(body)

        pending_items = [
            item
            for item in items
            if not item.checked and not item.status.startswith("error-")
        ]

        if not pending_items:
            logger.info("No pending backports found.")
            return 0

        logger.info("Found %d pending backports to process.", len(pending_items))

        # Determine branch name from issue title
        issue_title = self.gh.get_issue_title(args.issue)
        version_match = RELEASE_TITLE_RE.search(issue_title)
        if not version_match:
            logger.error("Could not parse version from issue title: %s", issue_title)
            return 1

        version = version_match.group(1)
        branch_version = ".".join(version.split(".")[:2])
        branch_name = f"release/{branch_version}"

        # Determine next RC tag to write to backport metadata
        self.git.fetch(args.remote, tags=True, force=True)
        latest_rc = get_latest_rc_tag(version, remote=args.remote)
        if not latest_rc:
            next_rc_suffix = "rc0"
        else:
            rc_num = int(latest_rc.split("-rc")[-1])
            next_rc_suffix = f"rc{rc_num + 1}"

        # Resolve PRs to merge commits using gh helper.
        pr_commit_infos = self.gh.get_merge_commits_for_prs(pending_items)

        shas, sha_to_item, failed_prs, ignored_prs, body = (
            self._process_pr_commit_infos(
                pr_commit_infos, body, args.issue, args.dry_run
            )
        )

        if not shas:
            logger.info("No valid merge commits to process.")
            if failed_prs:
                logger.error("Failed PRs:")
                for pr in failed_prs:
                    logger.error("- %s", pr)
                return 1
            return 0

        # Verify workspace is clean before proceeding
        if self.git.status():
            logger.error(
                "Git workspace is dirty. Please commit or stash changes"
                " before running backports."
            )
            return 1

        # Sort chronologically using git helper
        sorted_shas = self.git.sort_commits_chronologically(shas)

        self.git.fetch(args.remote)
        self.git.checkout(branch_name, track_remote=args.remote)
        start_sha = self.git.get_commit_sha("HEAD")

        try:
            result = self._cherry_pick_and_update_prs(
                sorted_shas,
                sha_to_item,
                body,
                args.issue,
                args.remote,
                args.dry_run,
                version,
                branch_name,
                next_rc_suffix,
            )
            failed_prs.extend(result.failed_prs)
            body = result.body
        finally:
            if args.dry_run:
                logger.info(
                    "[DRY RUN] Resetting branch %s to %s",
                    branch_name,
                    start_sha,
                )
                self.git.reset_hard(reset_to=start_sha)

        if failed_prs:
            logger.error("One or more cherry-picks/resolutions failed:")
            for pr in failed_prs:
                logger.error("- %s", pr)
            return 1

        if args.dry_run:
            logger.info("Dry run completed successfully. No errors found.")
        else:
            logger.info("All backports successfully processed!")
        return 0

    @classmethod
    def add_parser(cls, subparsers):
        """Adds parser for process-backports subcommand."""
        parser = subparsers.add_parser(
            "process-backports",
            help="Cherry-pick pending backports listed in the tracking issue.",
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
            "--add",
            type=parse_pr_list,
            help="PR references (numbers, #numbers, or URLs, comma/space separated) to add before processing.",
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

"""Subcommand to process pending backports."""

import argparse
import datetime
import hashlib
import logging
import os
import tempfile
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
    # List of news files collected from the successful cherry-picks.
    collected_news_files: list[str]
    # List of PR numbers that were successfully cherry-picked.
    successful_pr_nums: list[int]
    # List of tuples mapping successful PR numbers to their version marker diffs.
    collected_diffs: list[tuple[int, str]]
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
        collected_news_files = []
        successful_pr_nums = []
        collected_diffs = []
        for sha in sorted_shas:
            item = sha_to_item[sha]
            logger.info("Cherry-picking %s / %s...", item.pr_ref, sha)
            try:
                self.git.cherry_pick(sha)

                # Collect news files before they are deleted by update_changelog
                modified_files = self.git.get_modified_files("HEAD")
                for f in modified_files:
                    if changelog_news.is_news_file(f):
                        collected_news_files.append(f)

                # Replace version markers FIRST to isolate diff
                logger.info("Replacing version markers for PR %s...", item.pr_ref)
                replace_version_next(version)

                # Get diff of unstaged changes (version marker replacement)
                diff_content = self.git.diff()

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

                try:
                    pr_num = self.gh.resolve_pr_number(item.pr_ref)
                    if diff_content:
                        collected_diffs.append((pr_num, diff_content))
                    successful_pr_nums.append(pr_num)
                except Exception as e:
                    logger.warning(
                        "Failed to resolve PR number for %s: %s",
                        item.pr_ref,
                        format_exception(e),
                    )

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
            collected_news_files=collected_news_files,
            successful_pr_nums=successful_pr_nums,
            collected_diffs=collected_diffs,
            body=body,
        )

    def _sync_changelog_to_main(
        self,
        version: str,
        collected_news_files: list[str],
        successful_pr_nums: list[int],
        collected_diffs: list[tuple[int, str]],
        release_branch: str,
    ) -> None:
        args = self.args
        sorted_prs = sorted(successful_pr_nums)
        prs_str = ",".join(str(n) for n in sorted_prs)
        prs_hash = hashlib.sha256(prs_str.encode()).hexdigest()[:7]

        main_branch = "main"
        backport_branch = f"prepare-{version}-backports-{prs_hash}"

        logger.info(
            "Syncing changelog to %s via branch %s...",
            main_branch,
            backport_branch,
        )

        self.git.fetch(args.remote, refspec=main_branch)
        self.git.checkout(main_branch, track_remote=args.remote)
        main_start_sha = self.git.get_commit_sha("HEAD")

        failed_version_sync_prs = []
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

            logger.info(
                "Updating CHANGELOG.md and removing news files on %s...",
                backport_branch,
            )
            release_date = datetime.date.today().strftime("%Y-%m-%d")
            changelog_news.update_changelog(
                version,
                release_date,
                news_files=collected_news_files,
                delete_news=True,
            )

            # Apply version marker diffs
            failed_version_sync_prs = self._apply_version_marker_diffs(collected_diffs)

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
                    args.issue,
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

                if failed_version_sync_prs:
                    pr_body_lines.append("")
                    pr_body_lines.append(
                        "Warning: These PRs failed to update their version markers:"
                    )
                    for pr_num in sorted(failed_version_sync_prs):
                        pr_body_lines.append(f"- #{pr_num}")

                pr_body_lines.append("")
                pr_body_lines.append(f"Work towards #{args.issue}")
                pr_body_lines.append(f"Release-Tracking-Issue: #{args.issue}")
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
                        args.issue,
                    )
                    issue_body = self.gh.get_issue_body(args.issue)
                    for pr in successful_pr_nums:
                        task_name = f"Sync Changelog #{pr}"
                        metadata = {"status": "pending", "pr": f"#{pr_num}"}
                        issue_body = update_task_in_body(
                            issue_body,
                            task_name,
                            checked=False,
                            metadata=metadata,
                        )
                    self.gh.update_issue_body(args.issue, issue_body)
                except Exception as e:
                    logger.warning(
                        "Failed to update tracking issue or enable auto-merge: %s",
                        format_exception(e),
                    )
        finally:
            if args.dry_run:
                self.git.reset_hard(reset_to=main_start_sha)
            self.git.checkout(release_branch)

    def _apply_version_marker_diffs(
        self,
        collected_diffs: list[tuple[int, str]],
    ) -> list[int]:
        """Applies version marker diffs on main branch and returns failed PR numbers."""
        args = self.args
        failed_version_sync_prs = []
        if not collected_diffs:
            return failed_version_sync_prs

        with tempfile.TemporaryDirectory() as temp_dir:
            logger.info("Applying %d version marker patches...", len(collected_diffs))
            for pr_num, diff_content in collected_diffs:
                if args.dry_run:
                    logger.info(
                        "[DRY RUN] Would check and apply version marker patch"
                        " for PR #%s",
                        pr_num,
                    )

                patch_filepath = os.path.join(temp_dir, f"{pr_num}.patch")
                with open(patch_filepath, "w", encoding="utf-8") as f:
                    f.write(diff_content)

                if self.git.apply_check(patch_filepath):
                    if args.dry_run:
                        logger.info(
                            "[DRY RUN] Version marker patch for PR #%s applies"
                            " cleanly.",
                            pr_num,
                        )
                    else:
                        logger.info(
                            "Applying version marker patch for PR #%s...",
                            pr_num,
                        )
                        self.git.apply(patch_filepath)
                else:
                    logger.warning(
                        "Version marker patch for PR #%s could not be applied"
                        " cleanly to main. Skipping.",
                        pr_num,
                    )
                    failed_version_sync_prs.append(pr_num)
        return failed_version_sync_prs

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

        collected_news_files = []
        successful_pr_nums = []
        collected_diffs = []
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
            collected_news_files.extend(result.collected_news_files)
            successful_pr_nums.extend(result.successful_pr_nums)
            collected_diffs.extend(result.collected_diffs)
            body = result.body
        finally:
            if args.dry_run:
                logger.info(
                    "[DRY RUN] Resetting branch %s to %s",
                    branch_name,
                    start_sha,
                )
                self.git.reset_hard(reset_to=start_sha)

        if successful_pr_nums:
            self._sync_changelog_to_main(
                version,
                collected_news_files,
                successful_pr_nums,
                collected_diffs,
                branch_name,
            )

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

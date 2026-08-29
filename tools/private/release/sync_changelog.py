"""Subcommand to create sync PR to main for backports in a release."""

import argparse
import hashlib
import logging
import os
import traceback

from tools.private.release.gh import (
    SYNC_CHANGELOG_LABEL,
    GitHub,
    GitHubInterface,
    get_github_event_issue_number,
)
from tools.private.release.git import Git
from tools.private.release.process_news import ProcessNews
from tools.private.release.release_issue import (
    RELEASE_TITLE_RE,
    parse_checklist_state,
    update_task_in_body,
)
from tools.private.release.utils import (
    format_exception,
    parse_pr_list,
)

logger = logging.getLogger(__name__)

SYNC_CHANGELOG_SUCCESS_COMMENT_TEMPLATE = "Sync changelog PR created: {pr_url}"

SYNC_CHANGELOG_FAILURE_COMMENT_TEMPLATE = (
    "Warning: Failed to create sync PR to main for backports. {action_url_text}"
)


def _get_workflow_action_url_text(repo: str = "") -> str:
    """Returns a link to the GitHub Actions run if available."""
    run_id = os.environ.get("GITHUB_RUN_ID")
    server_url = os.environ.get("GITHUB_SERVER_URL", "https://github.com")
    repository = (
        os.environ.get("GITHUB_REPOSITORY") or repo or "bazel-contrib/rules_python"
    )
    if run_id:
        action_url = f"{server_url}/{repository}/actions/runs/{run_id}"
        return f"See [workflow run]({action_url}) for logs."
    return "See workflow logs."


class SyncChangelog:
    """Class to sync changelog to main for backports in a release."""

    def __init__(self, args, git: Git, gh: GitHubInterface):
        self.args = args
        self.git = git
        self.gh = gh

    def run(self) -> int:
        """Executes the sync-changelog subcommand."""
        try:
            return self._run_internal()
        except Exception as e:
            logger.error("Unexpected error in sync-changelog: %s", format_exception(e))
            traceback.print_exc()
            return 1

    def _post_failure_comment(self, issue_num: int) -> None:
        """Posts a failure warning message to the tracking issue."""
        try:
            action_url_text = _get_workflow_action_url_text(self.gh.repo)
            comment_body = SYNC_CHANGELOG_FAILURE_COMMENT_TEMPLATE.format(
                action_url_text=action_url_text,
            )
            self.gh.post_issue_comment(issue_num, comment_body)
        except Exception as e:
            logger.warning(
                "Failed to post warning comment to issue #%d: %s",
                issue_num,
                format_exception(e),
            )

    def _run_internal(self) -> int:
        """Internal implementation of sync-changelog."""
        args = self.args
        issue_num = args.issue or get_github_event_issue_number()
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

        try:
            return self._sync_for_issue(issue_num)
        except Exception as e:
            err_msg = format_exception(e)
            logger.error(
                "Failed to sync changelog for issue #%d: %s", issue_num, err_msg
            )
            self._post_failure_comment(issue_num)
            raise

    def _sync_for_issue(self, issue_num: int) -> int:
        args = self.args
        body = self.gh.get_issue_body(issue_num)
        issue_title = self.gh.get_issue_title(issue_num)
        version_match = RELEASE_TITLE_RE.search(issue_title)
        if not version_match:
            err = f"Could not parse version from issue title: {issue_title}"
            logger.error(err)
            self._post_failure_comment(issue_num)
            return 1

        version = version_match.group(1)

        if args.prs:
            pending_prs = []
            for pr_ref in args.prs:
                try:
                    pr_num = self.gh.resolve_pr_number(pr_ref)
                    pending_prs.append(pr_num)
                except Exception as e:
                    err = f"Failed to resolve PR reference '{pr_ref}': {format_exception(e)}"
                    logger.error(err)
                    self._post_failure_comment(issue_num)
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
            err = "Git workspace is dirty. Please commit or stash changes before running sync-changelog."
            logger.error(err)
            self._post_failure_comment(issue_num)
            return 1

        sorted_prs = sorted(pending_prs)
        prs_str = ",".join(str(n) for n in sorted_prs)
        prs_hash = hashlib.sha256(prs_str.encode()).hexdigest()[:7]

        main_branch = "main"
        sync_branch = f"sync-changelog-{version}-{prs_hash}"

        self.git.fetch(args.remote, refspec=main_branch)
        self.git.checkout(main_branch, track_remote=args.remote)

        try:
            if self.git.branch_exists(sync_branch):
                self.git.checkout(sync_branch)
                self.git.reset_hard(reset_to=main_branch)
            else:
                self.git.checkout(sync_branch, create_branch=True)

            # Run ProcessNews to process news files and version markers
            process_news_args = argparse.Namespace(
                version=version,
                targets=[str(pr) for pr in sorted_prs],
            )
            process_news_runner = ProcessNews(process_news_args, gh=self.gh)
            ret = process_news_runner.run()
            if ret != 0:
                err = f"ProcessNews failed for targets: {sorted_prs}"
                logger.error(err)
                self._post_failure_comment(issue_num)
                return 1

            if not self.git.status():
                logger.info("No changes to sync after running process-news.")
                return 0

            self.git.add_modified_and_deleted()
            self.git.commit(f"chore(release): sync changelog for v{version} backports")
            self.git.push(args.remote, sync_branch, set_upstream=True, force=True)

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
                labels=[SYNC_CHANGELOG_LABEL],
            )
            logger.info("Created PR: %s", pr_url)

            pr_num = int(pr_url.split("/")[-1])
            try:
                logger.info("Enabling auto-merge for PR #%s...", pr_num)
                self.gh.enable_auto_merge(pr_num)
            except Exception as e:
                logger.warning(
                    "Failed to enable auto-merge on PR #%s: %s",
                    pr_num,
                    format_exception(e),
                )

            try:
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
                    "Failed to update tracking issue checklist: %s",
                    format_exception(e),
                )

            try:
                success_body = SYNC_CHANGELOG_SUCCESS_COMMENT_TEMPLATE.format(
                    pr_url=pr_url,
                )
                self.gh.post_issue_comment(issue_num, success_body)
            except Exception as e:
                logger.warning(
                    "Failed to post success comment to issue #%s: %s",
                    issue_num,
                    format_exception(e),
                )
        finally:
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
            help="The tracking issue number (optional; extracted from GITHUB_EVENT_PATH or auto-discovered if omitted).",
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
        parser.set_defaults(command=cls.run_from_args)

    @classmethod
    def run_from_args(cls, args):
        """Instantiates and runs the command from parsed args."""
        git = Git(".")
        gh = GitHub()
        return cls(args, git, gh).run()

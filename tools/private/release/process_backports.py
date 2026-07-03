"""Subcommand to process pending backports."""

import argparse
import datetime
from typing import Any

from tools.private.release import changelog_news
from tools.private.release.gh import GH_REACTION_THUMBS_DOWN, GitHub
from tools.private.release.git import Git
from tools.private.release.release_issue import (
    RELEASE_TITLE_RE,
    add_backports_to_body,
    parse_backports,
    update_task_in_body,
)
from tools.private.release.utils import (
    get_latest_rc_tag,
    parse_pr_list,
    replace_version_next,
)


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
                print(f"PR {item.pr_ref} is open or draft. Ignoring.")
                ignored_prs.append(item.pr_ref)
            else:
                failed_prs.append(item.pr_ref)
                status_to_set = item.status or "error-unmerged-pr"
                if dry_run:
                    print(
                        f"[DRY RUN] Would update tracking issue checklist for"
                        f" unresolved PR {item.pr_ref} to status={status_to_set}"
                    )
                else:
                    print(
                        f"Updating tracking issue checklist for unresolved PR"
                        f" {item.pr_ref}..."
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
                        print(
                            f"ERROR: Failed to update tracking issue for"
                            f" unresolved PR {item.pr_ref}: {e}"
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
    ) -> tuple[list[str], str]:
        failed_prs = []
        for sha in sorted_shas:
            item = sha_to_item[sha]
            print(f"Cherry-picking {item.pr_ref} / {sha}...")
            try:
                self.git.cherry_pick(sha)

                # Perform news processing (merging news/ files into the changelog)
                print(f"Merging news fragments into changelog for PR {item.pr_ref}...")
                release_date = datetime.date.today().strftime("%Y-%m-%d")
                changelog_news.update_changelog(version, release_date)

                # Replace version markers that might have been introduced by the backport
                print(f"Replacing version markers for PR {item.pr_ref}...")
                replace_version_next(version)

                # Stage changelog changes, news/ deletions, and version placeholder updates
                self.git.add_modified_and_deleted()

                # Amend cherry-pick commit to include news merging and deletions,
                # and reference the release tracking issue.
                print(f"Amending cherry-pick commit for PR {item.pr_ref}...")
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
                    print(f"Updating tracking issue checklist for PR {item.pr_ref}...")
                    try:
                        body = update_task_in_body(
                            body, item.pr_ref, checked=True, metadata=metadata
                        )
                        self.gh.update_issue_body(issue, body)
                    except Exception as e:
                        print(
                            f"ERROR: Failed to update tracking issue for PR"
                            f" {item.pr_ref}: {e}"
                        )
                    print(f"Success: backported {item.pr_ref} / {sha} to {branch_name}")
                else:
                    print(
                        f"[DRY RUN] Success: {item.pr_ref} / {sha} can be"
                        f" backported without error."
                    )
                    print(
                        f"[DRY RUN] Would update tracking issue checklist for"
                        f" PR {item.pr_ref} to status=done"
                    )
            except Exception as e:
                print(f"ERROR: Conflict or error on {sha}: {e}. Aborting.")
                try:
                    self.git.cherry_pick_abort()
                except Exception:
                    pass
                failed_prs.append(item.pr_ref)

                if dry_run:
                    print(
                        f"[DRY RUN] Would update tracking issue checklist for"
                        f" failed PR {item.pr_ref} to status=error-merge-conflict"
                    )
                else:
                    print(
                        f"Updating tracking issue checklist for failed PR"
                        f" {item.pr_ref}..."
                    )
                    try:
                        body = update_task_in_body(
                            body,
                            item.pr_ref,
                            checked=False,
                            metadata={"status": "error-merge-conflict"},
                        )
                        self.gh.update_issue_body(issue, body)
                        print(
                            f"Updated back port of {item.pr_ref} to"
                            f" status=error-merge-conflict (unchecked)"
                        )
                    except Exception as e:
                        print(
                            f"ERROR: Failed to update tracking issue for"
                            f" failed PR {item.pr_ref}: {e}"
                        )
        return failed_prs, body

    def run(self) -> int:
        """Executes the process-backports subcommand."""
        args = self.args
        exit_code = 0
        try:
            exit_code = self._run_internal()
        except Exception as e:
            print(f"Unexpected error: {e}")
            exit_code = 1

        if exit_code != 0 and args.triggering_comment:
            print(f"Reacting with thumbs-down to comment {args.triggering_comment}...")
            try:
                self.gh.add_comment_reaction(
                    args.triggering_comment, GH_REACTION_THUMBS_DOWN
                )
            except Exception as e:
                print(f"Failed to add reaction to comment: {e}")

        return exit_code

    def _run_internal(self) -> int:
        """Internal implementation of process-backports."""
        args = self.args
        body = self.gh.get_issue_body(args.issue)

        if args.add:
            print(f"Adding backports {args.add} to tracking issue #{args.issue}...")
            try:
                body = add_backports_to_body(body, args.add)
            except ValueError as e:
                print(f"Error: {e}")
                return 1

            if not args.dry_run:
                self.gh.update_issue_body(args.issue, body)
                print("Successfully updated tracking issue checklist.")
            else:
                print(
                    "[DRY RUN] Would update tracking issue checklist with new"
                    " backports."
                )

        items = parse_backports(body)

        pending_items = [
            item
            for item in items
            if not item.checked and not item.status.startswith("error-")
        ]

        if not pending_items:
            print("No pending backports found.")
            return 0

        print(f"Found {len(pending_items)} pending backports to process.")

        # Determine branch name from issue title
        issue_title = self.gh.get_issue_title(args.issue)
        version_match = RELEASE_TITLE_RE.search(issue_title)
        if not version_match:
            print(f"Error: Could not parse version from issue title: {issue_title}")
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
            print("No valid merge commits to process.")
            if failed_prs:
                print("Failed PRs:")
                for pr in failed_prs:
                    print(f"- {pr}")
                return 1
            return 0

        # Verify workspace is clean before proceeding
        if self.git.status():
            print(
                "ERROR: Git workspace is dirty. Please commit or stash changes"
                " before running backports."
            )
            return 1

        # Sort chronologically using git helper
        sorted_shas = self.git.sort_commits_chronologically(shas)

        self.git.fetch(args.remote)
        self.git.checkout(branch_name, track_remote=args.remote)
        start_sha = self.git.get_commit_sha("HEAD")

        try:
            new_failed_prs, body = self._cherry_pick_and_update_prs(
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
            failed_prs.extend(new_failed_prs)
        finally:
            if args.dry_run:
                print(f"[DRY RUN] Resetting branch {branch_name} to {start_sha}")
                self.git.reset_hard(start_sha)

        if failed_prs:
            print("ERROR: One or more cherry-picks/resolutions failed:")
            for pr in failed_prs:
                print(f"- {pr}")
            return 1

        if args.dry_run:
            print("Dry run completed successfully. No errors found.")
        else:
            print("All backports successfully processed!")
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
            help="PR numbers (comma or space separated) to add before processing.",
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

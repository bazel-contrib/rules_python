"""Subcommand to process pending backports."""

import datetime
from typing import Any

from tools.private.release import changelog_news, gh, git
from tools.private.release.release_issue import (
    RELEASE_TITLE_RE,
    parse_backports,
    update_task_in_body,
)
from tools.private.release.utils import get_latest_rc_tag


def _process_pr_commit_infos(
    pr_commit_infos, body, issue, dry_run
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
                    f"[DRY RUN] Would update tracking issue checklist for unresolved PR {item.pr_ref} to status={status_to_set}"
                )
            else:
                print(
                    f"Updating tracking issue checklist for unresolved PR {item.pr_ref}..."
                )
                try:
                    body = update_task_in_body(
                        body,
                        item.pr_ref,
                        checked=False,
                        metadata={"status": status_to_set},
                    )
                    gh.update_issue_body(issue, body)
                except Exception as e:
                    print(
                        f"ERROR: Failed to update tracking issue for unresolved PR {item.pr_ref}: {e}"
                    )
    return shas, sha_to_item, failed_prs, ignored_prs, body


def _cherry_pick_and_update_prs(
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
            git.cherry_pick(sha)

            # Perform news processing (merging news/ files into the changelog)
            print(f"Merging news fragments into changelog for PR {item.pr_ref}...")
            release_date = datetime.date.today().strftime("%Y-%m-%d")
            changelog_news.update_changelog(version, release_date)

            # Stage changelog changes and news/ deletions
            git.add("CHANGELOG.md", "news/")

            # Amend cherry-pick commit to include news merging and deletions,
            # and reference the release tracking issue.
            print(f"Amending cherry-pick commit for PR {item.pr_ref}...")
            current_msg = git.get_commit_message("HEAD")
            new_msg = f"{current_msg.strip()}\n\nWork towards #{issue}"
            git.commit(new_msg, amend=True)

            if not dry_run:
                # Push amended commit
                git.push(remote, branch_name)

                new_sha = git.get_commit_sha("HEAD", short=True)
                metadata = {"status": "done", "rc": next_rc_suffix, "commit": new_sha}
                print(f"Updating tracking issue checklist for PR {item.pr_ref}...")
                try:
                    body = update_task_in_body(
                        body, item.pr_ref, checked=True, metadata=metadata
                    )
                    gh.update_issue_body(issue, body)
                except Exception as e:
                    print(
                        f"ERROR: Failed to update tracking issue for PR {item.pr_ref}: {e}"
                    )
                print(f"Success: backported {item.pr_ref} / {sha} to {branch_name}")
            else:
                print(
                    f"[DRY RUN] Success: {item.pr_ref} / {sha} can be backported without error."
                )
                print(
                    f"[DRY RUN] Would update tracking issue checklist for PR {item.pr_ref} to status=done"
                )
        except Exception as e:
            print(f"ERROR: Conflict or error on {sha}: {e}. Aborting.")
            try:
                git.cherry_pick_abort()
            except Exception:
                pass
            failed_prs.append(item.pr_ref)

            if dry_run:
                print(
                    f"[DRY RUN] Would update tracking issue checklist for failed PR {item.pr_ref} to status=error-merge-conflict"
                )
            else:
                print(
                    f"Updating tracking issue checklist for failed PR {item.pr_ref}..."
                )
                try:
                    body = update_task_in_body(
                        body,
                        item.pr_ref,
                        checked=False,
                        metadata={"status": "error-merge-conflict"},
                    )
                    gh.update_issue_body(issue, body)
                    print(
                        f"Updated back port of {item.pr_ref} to status=error-merge-conflict (unchecked)"
                    )
                except Exception as e:
                    print(
                        f"ERROR: Failed to update tracking issue for failed PR {item.pr_ref}: {e}"
                    )
    return failed_prs, body


def cmd_process_backports(args):
    """Executes the process-backports subcommand."""
    body = gh.get_issue_body(args.issue)
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
    issue_title = gh.get_issue_title(args.issue)
    version_match = RELEASE_TITLE_RE.search(issue_title)
    if not version_match:
        print(f"Error: Could not parse version from issue title: {issue_title}")
        return 1

    version = version_match.group(1)
    branch_version = ".".join(version.split(".")[:2])
    branch_name = f"release/{branch_version}"

    # Determine next RC tag to write to backport metadata
    git.fetch(args.remote, tags=True, force=True)
    latest_rc = get_latest_rc_tag(version, remote=args.remote)
    if not latest_rc:
        next_rc_suffix = "rc0"
    else:
        rc_num = int(latest_rc.split("-rc")[-1])
        next_rc_suffix = f"rc{rc_num + 1}"

    # Resolve PRs to merge commits using gh helper.
    pr_commit_infos = gh.get_merge_commits_for_prs(pending_items)

    shas, sha_to_item, failed_prs, ignored_prs, body = _process_pr_commit_infos(
        pr_commit_infos, body, args.issue, args.dry_run
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
    if git.status():
        print(
            "ERROR: Git workspace is dirty. Please commit or stash changes before running backports."
        )
        return 1

    # Sort chronologically using git helper
    sorted_shas = git.sort_commits_chronologically(shas)

    git.fetch(args.remote)
    git.checkout(branch_name, track_remote=args.remote)
    start_sha = git.get_commit_sha("HEAD")

    try:
        new_failed_prs, body = _cherry_pick_and_update_prs(
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
            git.reset_hard(start_sha)

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

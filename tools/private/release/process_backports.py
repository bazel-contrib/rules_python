"""Subcommand to process pending backports."""

import datetime

from tools.private.release import changelog_news, gh, git
from tools.private.release.release_issue import (
    RELEASE_TITLE_RE,
    parse_backports,
    update_task_in_body,
)
from tools.private.release.utils import get_latest_rc_tag


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
            # Handle case where PR could not be resolved to a merge commit.
            # We immediately mark it as failed in the tracking issue.
            failed_prs.append(item.pr_ref)
            status_to_set = item.status or "error-unmerged-pr"
            if args.dry_run:
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
                    gh.update_issue_body(args.issue, body)
                except Exception as e:
                    print(
                        f"ERROR: Failed to update tracking issue for unresolved PR {item.pr_ref}: {e}"
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

    for sha in sorted_shas:
        item = sha_to_item[sha]
        print(f"Cherry-picking {item.pr_ref} / {sha}...")
        try:
            git.cherry_pick(sha, no_commit=args.dry_run)

            # Perform news processing (merging news/ files into the changelog)
            print(f"Merging news fragments into changelog for PR {item.pr_ref}...")
            release_date = datetime.date.today().strftime("%Y-%m-%d")
            changelog_news.update_changelog(version, release_date)

            if not args.dry_run:
                # Stage changelog changes and news/ deletions
                git.add("CHANGELOG.md", "news/")

                # Amend cherry-pick commit to include news merging and deletions,
                # and reference the release tracking issue.
                print(f"Amending cherry-pick commit for PR {item.pr_ref}...")
                current_msg = git.get_commit_message("HEAD")
                new_msg = f"{current_msg.strip()}\n\nWork towards #{args.issue}"
                git.commit(new_msg, amend=True)

                # Push amended commit
                git.push(args.remote, branch_name)

                new_sha = git.get_commit_sha("HEAD", short=True)
                metadata = {"status": "done", "rc": next_rc_suffix, "commit": new_sha}
                print(f"Updating tracking issue checklist for PR {item.pr_ref}...")
                try:
                    body = update_task_in_body(
                        body, item.pr_ref, checked=True, metadata=metadata
                    )
                    gh.update_issue_body(args.issue, body)
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

            if args.dry_run:
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
                    gh.update_issue_body(args.issue, body)
                    print(
                        f"Updated back port of {item.pr_ref} to status=error-merge-conflict (unchecked)"
                    )
                except Exception as e:
                    print(
                        f"ERROR: Failed to update tracking issue for failed PR {item.pr_ref}: {e}"
                    )
        finally:
            if args.dry_run:
                git.reset_hard("HEAD")

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

import datetime
import pathlib

from tools.private.release import changelog_news, gh, git
from tools.private.release.release_issue import update_task_in_body
from tools.private.release.utils import (
    determine_next_version,
    replace_version_next,
)


def cmd_prepare(args):
    """Executes the prepare subcommand."""
    print("Fetching upstream to verify fresh release history...")
    git.fetch(tags=True, force=True)

    # Run pre-check: verify there are no local edits
    status = git.status()
    if status:
        print(
            "Error: Local edits detected. Workspace must be completely clean"
            " before running release preparation."
        )
        for line in status.splitlines():
            print(f"  {line}")
        return 1
    print("Pre-check passed: Workspace is clean.")

    version = args.version
    if version is None:
        version = determine_next_version()

    print(f"Running preparation pipeline for {version}...")

    # 1. Find or create tracking issue (EARLY)
    # We do this before any write operations (branch creation, commit, push)
    issue_num = args.issue

    if not issue_num:
        try:
            issue_num = gh.get_release_tracking_issue(version)
            print(f"Tracking issue: #{issue_num}")
        except gh.MultipleTrackingIssuesError as e:
            print(f"Error: {e}")
            return 1
        except gh.NoTrackingIssueError:
            # Not found, we need the template
            template_path = pathlib.Path(
                ".github/ISSUE_TEMPLATE/release_tracking_template.md"
            )
            if not template_path.exists():
                raise FileNotFoundError(f"Template file not found at {template_path}")
            template_content = template_path.read_text(encoding="utf-8")

            if args.dry_run:
                print(
                    f"[DRY RUN] No active tracking issue found for {version}. Would create a new one."
                )
                print(f"[DRY RUN] Title: Release {version}\n{template_content}")
                issue_num = None  # Keep it None for dry-run prints later
            else:
                print(
                    f"No active tracking issue found for {version}. Creating a new one..."
                )
                issue_num = gh.create_tracking_issue(version, template_content)
                print(f"Tracking issue: #{issue_num}")
    else:
        print(f"Tracking issue: #{issue_num}")

    branch_name = f"prepare-{version}"

    # 2. Interleaved git and write operations

    # --- Branch selection/creation ---
    if git.branch_exists(branch_name):
        if args.dry_run:
            print(
                f"[DRY RUN] Branch {branch_name} already exists. Would checkout existing branch."
            )
        else:
            print(f"Branch {branch_name} already exists. Checking it out...")
            git.checkout(branch_name)
    else:
        if args.dry_run:
            print(f"[DRY RUN] Would create and checkout branch {branch_name}")
        else:
            git.checkout(branch_name, create_branch=True)

    # --- Update files ---
    if args.dry_run:
        print(
            f"[DRY RUN] Would update CHANGELOG.md and version placeholders for {version}"
        )
    else:
        print("Updating changelog and placeholders...")
        release_date = datetime.date.today().strftime("%Y-%m-%d")
        changelog_news.update_changelog(version, release_date)
        replace_version_next(version)

    # --- Commit and Push ---
    if args.dry_run:
        print(f"[DRY RUN] Would push branch {branch_name} to origin")
    else:
        modified_files = git.status()
        if not modified_files:
            print("No files modified by the release tool. Nothing to commit.")
            return 0

        # Stage all modified and deleted tracked files
        git.add_modified_and_deleted()

        git.commit(f"Prepare release {version}")
        git.push("origin", branch_name, set_upstream=True)

    # --- Create PR ---
    if args.dry_run:
        target_issue = f"#{issue_num}" if issue_num else "<NEW_ISSUE>"
        print(
            f"[DRY RUN] Would create Pull Request for branch {branch_name} targeting issue {target_issue}"
        )
    else:
        pr_url = gh.create_pr(version, issue_num)
        pr_num = pr_url.split("/")[-1]
        print(f"Created Pull Request: {pr_url} (PR #{pr_num})")

    # --- Update checklist ---
    if args.dry_run:
        target_issue = f"#{issue_num}" if issue_num else "<NEW_ISSUE>"
        print(
            f"[DRY RUN] Would update tracking issue {target_issue} checklist 'Prepare Release' task status to PENDING"
        )
    else:
        print(
            f"Updating tracking issue #{issue_num} checklist 'Prepare Release' task status to PENDING..."
        )
        body = gh.get_issue_body(issue_num)
        metadata = {"status": "pending", "pr": f"#{pr_num}"}
        updated_body = update_task_in_body(
            body, "Prepare Release", checked=False, metadata=metadata
        )
        gh.update_issue_body(issue_num, updated_body)
        print("Preparation pipeline completed successfully!")

    return 0

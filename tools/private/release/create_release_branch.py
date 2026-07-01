"""Subcommand to create a release branch from a merged PR commit."""

from tools.private.release import gh, git
from tools.private.release.release_issue import (
    RELEASE_TITLE_RE,
    parse_checklist_state,
    update_task_in_body,
)
from tools.private.release.utils import REPO_URL


def cmd_create_release_branch(args):
    """Executes the create-release-branch subcommand."""
    print(f"Evaluating branch creation for tracking issue #{args.issue}...")
    body = gh.get_issue_body(args.issue)
    state = parse_checklist_state(body)

    if (
        state["prepare_release"]["status"] != "done"
        or not state["prepare_release"]["commit"]
    ):
        print(
            "Error: Prepare Release task is not marked 'done' with a valid commit SHA."
        )
        return 1

    if state["create_branch"]["checked"]:
        print("Release branch has already been created and checked. Skipping.")
        return 0

    # Extract version from issue title
    issue_title = gh.get_issue_title(args.issue)
    version_match = RELEASE_TITLE_RE.search(issue_title)
    if not version_match:
        print(f"Error: Could not parse version from issue title: {issue_title}")
        return 1

    version = version_match.group(1)
    branch_version = ".".join(version.split(".")[:2])
    branch_name = f"release/{branch_version}"

    commit_sha = state["prepare_release"]["commit"]
    print(f"Cutting branch {branch_name} from commit {commit_sha}...")

    # Create and push branch without affecting local checkout
    git.fetch(args.remote)

    if git.remote_branch_exists(args.remote, branch_name):
        remote_ref = f"{args.remote}/{branch_name}"
        remote_sha = git.get_commit_sha(remote_ref)
        if remote_sha == commit_sha:
            print(
                f"Branch {branch_name} already exists on {args.remote} and points to {commit_sha}. Skipping push."
            )
        elif git.is_ancestor(remote_ref, commit_sha):
            print(
                f"Branch {branch_name} exists on {args.remote} but can be fast-forwarded to {commit_sha}. Pushing..."
            )
            ref_spec = f"{commit_sha}:refs/heads/{branch_name}"
            git.push(args.remote, ref_spec)
        else:
            print(
                f"Error: Branch {branch_name} already exists on {args.remote} at {remote_sha[:8]}, "
                f"which is not an ancestor of {commit_sha[:8]}. Cannot fast-forward."
            )
            return 1
    else:
        print(f"Branch {branch_name} does not exist on {args.remote}. Pushing...")
        ref_spec = f"{commit_sha}:refs/heads/{branch_name}"
        git.push(args.remote, ref_spec)
        print(
            f"Successfully pushed branch {branch_name} pointing to {commit_sha} to {args.remote}"
        )

    # Update tracking issue checklist
    print("Updating tracking issue checklist...")
    branch_url = f"{REPO_URL}/tree/{branch_name}"
    metadata = {"status": "done", "branch_url": branch_url, "commit": commit_sha[:8]}
    updated_body = update_task_in_body(
        body, "Create Release branch", checked=True, metadata=metadata
    )
    gh.update_issue_body(args.issue, updated_body)
    print("Create Release branch task marked complete successfully!")
    return 0

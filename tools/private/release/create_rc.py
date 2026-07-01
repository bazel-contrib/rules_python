"""Subcommand to tag and push the next release candidate."""

from tools.private.release import gh, git
from tools.private.release.release_issue import (
    RELEASE_TITLE_RE,
    parse_backports,
    parse_checklist_state,
    update_task_in_body,
)
from tools.private.release.utils import (
    REPO_URL,
    get_latest_rc_tag,
)


def cmd_create_rc(args):
    """Executes the create-rc subcommand."""
    body = gh.get_issue_body(args.issue)
    state = parse_checklist_state(body)

    if (
        state["prepare_release"]["status"] != "done"
        or state["create_branch"]["status"] != "done"
    ):
        print(
            "Error: Preconditions not met (release must be prepared and branch created)."
        )
        return 1

    # Gating: RC tagging is blocked if any backport is unchecked OR does not have status=done
    backports = parse_backports(body)
    conflicting_or_pending = [
        b for b in backports if not b["checked"] or b["status"] != "done"
    ]
    if conflicting_or_pending:
        print(
            f"Gating RC tagging: {len(conflicting_or_pending)} backports are still"
            " unfinished, failed, or in conflict."
        )
        return 1

    # Resolve version and branch
    issue_title = gh.get_issue_title(args.issue)
    version_match = RELEASE_TITLE_RE.search(issue_title)
    if not version_match:
        print(f"Error: Could not parse version from issue title: {issue_title}")
        return 1

    version = version_match.group(1)
    branch_version = ".".join(version.split(".")[:2])
    branch_name = f"release/{branch_version}"

    # Determine next RC tag
    git.fetch(args.remote)
    git.fetch(args.remote, tags=True, force=True)
    latest_rc = get_latest_rc_tag(version, remote=args.remote)

    if not latest_rc:
        next_rc_num = 0
        next_rc = f"{version}-rc0"
    else:
        rc_num = int(latest_rc.split("-rc")[-1])
        next_rc_num = rc_num + 1
        next_rc = f"{version}-rc{next_rc_num}"

    # Precheck: next RC number must exist and be unchecked in the checklist
    rc_tags = state.get("rc_tags", {})
    if next_rc_num not in rc_tags:
        print(
            f"Error: Checklist is missing required task 'Tag RC{next_rc_num}'"
            f" to cut {version}-rc{next_rc_num}."
        )
        return 1

    target_rc_task = rc_tags[next_rc_num]
    if target_rc_task["checked"] or target_rc_task["status"] == "done":
        print(
            f"Error: Task 'Tag RC{next_rc_num}' is already marked done in the checklist."
        )
        return 1

    target_ref = f"{args.remote}/{branch_name}"
    commit_sha = git.get_commit_sha(target_ref)

    print(f"Tagging and pushing next RC: {next_rc}...")
    git.tag(next_rc, target_ref)
    git.push(args.remote, next_rc)

    # Check off the appropriate "Tag RC{N}" task in the checklist
    print(f"Checking off Tag RC{next_rc_num} task...")
    metadata = {"status": "done", "tag": next_rc, "commit": commit_sha[:8]}
    task_name = f"Tag RC{next_rc_num}"
    updated_body = update_task_in_body(body, task_name, checked=True, metadata=metadata)
    gh.update_issue_body(args.issue, updated_body)

    tag_url = f"{REPO_URL}/releases/tag/{next_rc}"
    bcr_search_url = f"https://github.com/bazelbuild/bazel-central-registry/pulls?q=is%3Apr+rules_python+{version}"
    release_workflow_url = f"{REPO_URL}/actions/workflows/release.yml"
    comment_body = f"""**New Release Candidate Tagged!** 🐍🌿

Release Candidate **{next_rc}** has been successfully generated and tagged on branch `{branch_name}`.

- View Tag: [{next_rc}]({tag_url})
- Track BCR Progress: [Search BCR Pull Requests]({bcr_search_url})
- Trigger Release Workflow: [Release Workflow]({release_workflow_url})"""
    gh.post_issue_comment(args.issue, comment_body)
    print("RC creation completed successfully!")
    return 0

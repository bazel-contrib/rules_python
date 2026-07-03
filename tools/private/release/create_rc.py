"""Subcommand to tag and push the next release candidate."""

from tools.private.release.gh import GitHub
from tools.private.release.git import Git
from tools.private.release.release_issue import (
    RELEASE_TITLE_RE,
    add_rc_task_to_body,
    parse_backports,
    parse_checklist_state,
    update_task_in_body,
)
from tools.private.release.utils import (
    REPO_URL,
    get_latest_rc_tag,
)


class CreateRc:
    """Class to tag and push the next release candidate."""

    def __init__(self, args, git: Git, gh: GitHub):
        self.args = args
        self.git = git
        self.gh = gh

    def run(self) -> int:
        """Executes the create-rc subcommand."""
        args = self.args
        body = self.gh.get_issue_body(args.issue)
        state = parse_checklist_state(body)

        if (
            state["prepare_release"].status != "done"
            or state["create_branch"].status != "done"
        ):
            print(
                "Error: Preconditions not met (release must be prepared and"
                " branch created)."
            )
            return 1

        # Gating: RC tagging is blocked if any backport is unchecked OR does not have status=done
        backports = parse_backports(body)
        conflicting_or_pending = [
            b for b in backports if not b.checked or b.status != "done"
        ]
        if conflicting_or_pending:
            print(
                f"Gating RC tagging: {len(conflicting_or_pending)} backports"
                " are still unfinished, failed, or in conflict."
            )
            return 1

        # Resolve version and branch
        issue_title = self.gh.get_issue_title(args.issue)
        version_match = RELEASE_TITLE_RE.search(issue_title)
        if not version_match:
            print(f"Error: Could not parse version from issue title: {issue_title}")
            return 1

        version = version_match.group(1)
        branch_version = ".".join(version.split(".")[:2])
        branch_name = f"release/{branch_version}"

        # Determine next RC tag
        self.git.fetch(args.remote)
        self.git.fetch(args.remote, tags=True, force=True)
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
            print(f"Task 'Tag RC{next_rc_num}' not found in checklist. Adding it...")
            body = add_rc_task_to_body(body, next_rc_num)
            self.gh.update_issue_body(args.issue, body)
        else:
            target_rc_task = rc_tags[next_rc_num]
            if target_rc_task.checked or target_rc_task.status == "done":
                print(
                    f"Error: Task 'Tag RC{next_rc_num}' is already marked done in"
                    " the checklist."
                )
                return 1

        target_ref = f"{args.remote}/{branch_name}"
        commit_sha = self.git.get_commit_sha(target_ref)

        print(f"Tagging and pushing next RC: {next_rc}...")
        self.git.tag(next_rc, target_ref)
        self.git.push(args.remote, next_rc)

        import os

        if "GITHUB_OUTPUT" in os.environ:
            with open(os.environ["GITHUB_OUTPUT"], "a") as f:
                f.write(f"tag_name={next_rc}\n")

        # Check off the appropriate "Tag RC{N}" task in the checklist
        print(f"Checking off Tag RC{next_rc_num} task...")
        metadata = {"status": "done", "tag": next_rc, "commit": commit_sha[:8]}
        task_name = f"Tag RC{next_rc_num}"
        updated_body = update_task_in_body(
            body, task_name, checked=True, metadata=metadata
        )
        self.gh.update_issue_body(args.issue, updated_body)

        tag_url = f"{REPO_URL}/releases/tag/{next_rc}"
        bcr_entry_url = f"https://registry.bazel.build/modules/rules_python/{next_rc}"
        bcr_search_url = f"https://github.com/bazelbuild/bazel-central-registry/pulls?q=is%3Apr+rules_python+{next_rc}"
        if run_id := os.environ.get("GITHUB_RUN_ID"):
            release_workflow_url = f"{REPO_URL}/actions/runs/{run_id}"
        else:
            release_workflow_url = (
                f"{REPO_URL}/actions/workflows/release_create_rc.yaml"
            )
        branch_url = f"{REPO_URL}/tree/{branch_name}"
        comment_body = f"""**New Release Candidate Tagged!** 🐍🌿

Release Candidate **{next_rc}** has been successfully generated and tagged on branch [`{branch_name}`]({branch_url}).

- [Github Release {next_rc}]({tag_url})
- [BCR Entry {next_rc}]({bcr_entry_url})
- [BCR PRs]({bcr_search_url})
- [Release workflow status]({release_workflow_url})"""
        self.gh.post_issue_comment(args.issue, comment_body)
        print("RC creation completed successfully!")
        return 0

    @classmethod
    def add_parser(cls, subparsers):
        """Adds parser for create-rc subcommand."""
        parser = subparsers.add_parser(
            "create-rc",
            help="Tags the next RC on the release branch if no backports remain.",
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
            help="The git remote to push the RC tag to (required).",
        )
        parser.set_defaults(command=cls.run_from_args)

    @classmethod
    def run_from_args(cls, args):
        """Instantiates and runs the command from parsed args."""
        git = Git(".")
        gh = GitHub()
        return cls(args, git, gh).run()

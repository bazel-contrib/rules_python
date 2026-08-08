"""Subcommand to mark preparation task as complete."""

import re

from tools.private.release.gh import GitHub
from tools.private.release.release_issue import (
    parse_checklist_state,
    update_task_in_body,
)
from tools.private.release.utils import set_github_output


class CompletePrepare:
    """Class to mark preparation task as complete."""

    def __init__(self, args, gh: GitHub):
        self.args = args
        self.gh = gh

    def run(self) -> int:
        """Executes the complete-prepare subcommand (Phase 2 PR merged)."""
        args = self.args
        pr_number = args.pr
        issue_number = args.issue

        if not pr_number and not issue_number:
            print("Error: Either --pr or --issue must be provided.")
            return 1

        if not pr_number and issue_number:
            issue_body = self.gh.get_issue_body(issue_number)
            state = parse_checklist_state(issue_body)
            prep_task = state.get("prepare_release")
            if not prep_task or not prep_task.pr:
                print(
                    f"Error: Could not find PR reference for 'Prepare Release'"
                    f" in issue #{issue_number}."
                )
                return 1
            pr_number = int(prep_task.pr.lstrip("#"))

        print(f"Completing preparation for PR #{pr_number}...")

        pr_info = self.gh.get_pr_info(pr_number)
        if not pr_info or pr_info.get("state") != "MERGED":
            state = pr_info.get("state", "UNKNOWN") if pr_info else "NOT_FOUND"
            print(f"Error: PR #{pr_number} is not merged yet (state: {state}).")
            return 1

        if not issue_number:
            # Resolve issue number from PR body
            pr_body = pr_info.get("body") or ""
            match = re.search(r"Work towards #(\d+)", pr_body)
            if not match:
                match = re.search(r"#(\d+)", pr_body)
            if not match:
                print(
                    f"Error: Could not determine tracking issue number from PR"
                    f" #{pr_number} body: {pr_body}"
                )
                return 1

            issue_number = int(match.group(1))
            print(f"Resolved tracking issue #{issue_number} from PR #{pr_number} body.")

        commit_sha = pr_info["mergeCommit"]["oid"]
        short_commit = commit_sha[:8]
        print(
            f"PR #{pr_number} merged at commit {commit_sha}. Updating tracking issue..."
        )

        # Update checklist: mark Prepare Release as done (checked) and set SUCCESS
        body = self.gh.get_issue_body(issue_number)
        metadata = {
            "status": "done",
            "pr": f"#{pr_number}",
            "commit": short_commit,
        }
        updated_body = update_task_in_body(
            body, "Prepare Release", checked=True, metadata=metadata
        )
        self.gh.update_issue_body(issue_number, updated_body)
        print("Prepare Release task marked complete successfully!")

        set_github_output("issue", str(issue_number))

        return 0

    @classmethod
    def add_parser(cls, subparsers):
        """Adds parser for complete-prepare subcommand."""
        parser = subparsers.add_parser(
            "complete-prepare",
            help="Mark the Prepare Release task as complete in the tracking issue.",
        )
        parser.add_argument(
            "--pr",
            type=int,
            required=False,
            help="The merged preparation PR number.",
        )
        parser.add_argument(
            "--issue",
            type=int,
            required=False,
            help="The release tracking issue number.",
        )
        parser.set_defaults(command=cls.run_from_args)

    @classmethod
    def run_from_args(cls, args):
        """Instantiates and runs the command from parsed args."""
        gh = GitHub()
        return cls(args, gh).run()

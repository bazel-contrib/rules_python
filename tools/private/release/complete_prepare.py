"""Subcommand to mark preparation task as complete."""

import re

from tools.private.release.gh import GitHub
from tools.private.release.release_issue import update_task_in_body


class CompletePrepare:
    """Class to mark preparation task as complete."""

    def __init__(self, args, gh: GitHub):
        self.args = args
        self.gh = gh

    def run(self) -> int:
        """Executes the complete-prepare subcommand (Phase 2 PR merged)."""
        args = self.args
        print(f"Completing preparation for PR #{args.pr}...")

        pr_info = self.gh.get_pr_info(args.pr)
        if not pr_info or pr_info.get("state") != "MERGED":
            state = pr_info.get("state", "UNKNOWN")
            print(f"Error: PR #{args.pr} is not merged yet (state: {state}).")
            return 1

        # Resolve issue number from PR body
        pr_body = pr_info.get("body") or ""
        match = re.search(r"Work towards #(\d+)", pr_body)
        if not match:
            match = re.search(r"#(\d+)", pr_body)
        if not match:
            print(
                f"Error: Could not determine tracking issue number from PR"
                f" #{args.pr} body: {pr_body}"
            )
            return 1

        issue_num = int(match.group(1))
        print(f"Resolved tracking issue #{issue_num} from PR #{args.pr} body.")

        commit_sha = pr_info["mergeCommit"]["oid"]
        short_commit = commit_sha[:8]
        print(
            f"PR #{args.pr} merged at commit {commit_sha}. Updating tracking issue..."
        )

        # Update checklist: mark Prepare Release as done (checked) and set SUCCESS
        body = self.gh.get_issue_body(issue_num)
        metadata = {
            "status": "done",
            "pr": f"#{args.pr}",
            "commit": short_commit,
        }
        updated_body = update_task_in_body(
            body, "Prepare Release", checked=True, metadata=metadata
        )
        self.gh.update_issue_body(issue_num, updated_body)
        print("Prepare Release task marked complete successfully!")
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
            required=True,
            help="The merged preparation PR number.",
        )
        parser.set_defaults(command=cls.run_from_args)

    @classmethod
    def run_from_args(cls, args):
        """Instantiates and runs the command from parsed args."""
        gh = GitHub()
        return cls(args, gh).run()

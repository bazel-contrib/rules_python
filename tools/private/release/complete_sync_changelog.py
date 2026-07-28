"""Subcommand to mark sync changelog tasks as complete."""

import re

from tools.private.release.gh import GitHub
from tools.private.release.release_issue import (
    parse_checklist_state,
    update_task_in_body,
)


class CompleteSyncChangelog:
    """Class to mark sync changelog tasks as complete."""

    def __init__(self, args, gh: GitHub):
        self.args = args
        self.gh = gh

    def run(self) -> int:
        """Executes the complete-sync-changelog subcommand."""
        args = self.args
        print(f"Completing sync changelog for PR #{args.pr}...")

        pr_info = self.gh.get_pr_info(args.pr)
        if not pr_info or pr_info.get("state") != "MERGED":
            state = pr_info.get("state", "UNKNOWN")
            print(f"Error: PR #{args.pr} is not merged yet (state: {state}).")
            return 1

        # Resolve issue number from PR body using Release-Tracking-Issue: #<issue>
        pr_body = pr_info.get("body") or ""
        match = re.search(r"Release-Tracking-Issue:\s*#(\d+)", pr_body)
        if not match:
            print(
                f"Error: Could not find 'Release-Tracking-Issue: #<issue>' in"
                f" PR #{args.pr} body: {pr_body}"
            )
            return 1

        issue_num = int(match.group(1))
        print(f"Resolved tracking issue #{issue_num} from PR #{args.pr} body.")

        commit_sha = pr_info["mergeCommit"]["oid"]
        short_commit = commit_sha[:8]
        print(
            f"PR #{args.pr} merged at commit {commit_sha}. Updating tracking issue..."
        )

        # Update checklist: mark all Sync Changelog tasks pointing to this PR as done
        body = self.gh.get_issue_body(issue_num)
        state = parse_checklist_state(body)
        sync_changelogs = state.get("sync_changelogs", {})

        updated_any = False
        for pr_num, task in sync_changelogs.items():
            # Check if this task points to our merged PR
            task_pr = task.metadata.get("pr")
            if task_pr == f"#{args.pr}":
                print(f"Marking task '{task.name}' as complete...")
                metadata = {
                    "status": "done",
                    "pr": f"#{args.pr}",
                    "commit": short_commit,
                }
                body = update_task_in_body(
                    body, task.name, checked=True, metadata=metadata
                )
                updated_any = True

        if not updated_any:
            print(f"Warning: No 'Sync Changelog' tasks found pointing to PR #{args.pr}")
            return 0

        self.gh.update_issue_body(issue_num, body)
        print("Sync changelog tasks marked complete successfully!")
        return 0

    @classmethod
    def add_parser(cls, subparsers):
        """Adds parser for complete-sync-changelog subcommand."""
        parser = subparsers.add_parser(
            "complete-sync-changelog",
            help="Mark the Sync Changelog tasks as complete in the tracking issue.",
        )
        parser.add_argument(
            "--pr",
            type=int,
            required=True,
            help="The merged sync changelog PR number.",
        )
        parser.set_defaults(command=cls.run_from_args)

    @classmethod
    def run_from_args(cls, args):
        """Instantiates and runs the command from parsed args."""
        gh = GitHub()
        return cls(args, gh).run()

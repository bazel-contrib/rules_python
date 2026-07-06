"""Subcommand to add PRs to the release tracking issue backports checklist."""

from tools.private.release.gh import GitHub
from tools.private.release.release_issue import (
    add_backports_to_body,
    add_rc_task_to_body,
    add_sync_changelog_task_to_body,
    parse_checklist_state,
)


class AddBackports:
    """Class to add PRs to the release tracking issue."""

    def __init__(self, args, gh: GitHub):
        self.args = args
        self.gh = gh

    def run(self) -> int:
        """Executes the add-backports subcommand."""
        args = self.args

        issue_num = args.issue
        if not issue_num:
            print(
                "No issue specified. Trying to auto-discover active release"
                " tracking issue..."
            )
            try:
                open_issues = self.gh.get_open_tracking_issues()
                if not open_issues:
                    print("Error: No open release tracking issues found.")
                    return 1
                if len(open_issues) > 1:
                    print(
                        "Error: Multiple open release tracking issues found."
                        " Cannot determine active one:"
                    )
                    for issue in open_issues:
                        print(f"- #{issue['number']}: {issue['title']}")
                    return 1
                issue_num = open_issues[0]["number"]
                print(f"Auto-discovered active release tracking issue: #{issue_num}")
            except Exception as e:
                print(f"Error auto-discovering tracking issue: {e}")
                return 1

        resolved_prs = []
        for pr_ref in args.prs:
            try:
                pr_num = self.gh.resolve_pr_number(pr_ref)
                resolved_prs.append(pr_num)
            except Exception as e:
                print(f"Error resolving PR ref '{pr_ref}': {e}")
                return 1

        print(
            f"Adding backports {resolved_prs} (resolved from {args.prs}) to tracking issue #{issue_num}..."
        )
        try:
            body = self.gh.get_issue_body(issue_num)
            items_to_add = [{"ref": f"#{pr}"} for pr in resolved_prs]
            body = add_backports_to_body(body, items_to_add)
            for pr in resolved_prs:
                body = add_sync_changelog_task_to_body(body, pr)
            state = parse_checklist_state(body)
            rc_tags = state.get("rc_tags", {})
            has_pending_rc = any(
                not task.checked and task.status != "done" for task in rc_tags.values()
            )
            next_rc_num = max(rc_tags.keys()) + 1 if rc_tags else 0
            if not has_pending_rc:
                print(
                    f"No pending RC task found. Adding 'Tag"
                    f" RC{next_rc_num}' to checklist..."
                )
                body = add_rc_task_to_body(body, next_rc_num)
        except ValueError as e:
            print(f"Error: {e}")
            return 1
        except Exception as e:
            print(f"Failed to update tracking issue: {e}")
            return 1

        try:
            self.gh.update_issue_body(issue_num, body)
            print("Successfully updated tracking issue checklist.")
        except Exception as e:
            print(f"Failed to update tracking issue body: {e}")
            return 1

        return 0

    @classmethod
    def add_parser(cls, subparsers):
        """Adds parser for add-backports subcommand."""
        parser = subparsers.add_parser(
            "add-backports",
            help="Add PRs to the release tracking issue backports checklist.",
        )
        parser.add_argument(
            "prs",
            type=str,
            nargs="+",
            help="PR references (numbers, #numbers, or URLs) to add (positional, space-separated).",
        )
        parser.add_argument(
            "--issue",
            type=int,
            help="The tracking issue number. If omitted, will try to auto-discover the active release tracking issue.",
        )
        parser.set_defaults(command=cls.run_from_args)

    @classmethod
    def run_from_args(cls, args):
        """Instantiates and runs the command from parsed args."""
        gh = GitHub()
        return cls(args, gh).run()

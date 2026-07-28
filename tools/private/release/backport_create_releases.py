"""Subcommand to initiate releases for verified backports."""

import argparse
import pathlib
import re
from dataclasses import dataclass

from tools.private.release.backport_prepare import parse_backport_metadata
from tools.private.release.gh import GitHub
from tools.private.release.release_issue import (
    add_backports_to_body,
    add_sync_changelog_task_to_body,
    parse_metadata_line,
    update_task_in_body,
)


@dataclass
class BackportTasksState:
    # Map of minor version (e.g. "1.7") to verification status (e.g. "success", "failed-conflict")
    verify: dict[str, str]
    # Map of full version (e.g. "1.7.1") to tuple of (status, release_issue_number_or_None)
    release: dict[str, tuple[str, str | None]]


def parse_backport_tasks(body) -> BackportTasksState:
    """Parses tasks from backport issue body."""
    verify_tasks = {}
    release_tasks = {}

    lines = body.splitlines()
    for line in lines:
        parsed = parse_metadata_line(line)
        if not parsed:
            continue
        name = parsed["name"]
        meta = parsed["metadata"]

        verify_match = re.match(r"Verify apply (\d+\.\d+)", name, re.IGNORECASE)
        if verify_match:
            minor = verify_match.group(1)
            verify_tasks[minor] = meta.get("status", "pending")
            continue

        release_match = re.match(r"Track Release (\d+\.\d+\.\d+)", name, re.IGNORECASE)
        if release_match:
            version = release_match.group(1)
            status = meta.get("status", "pending")
            issue_num = meta.get("release_issue")
            release_tasks[version] = (status, issue_num)

    return BackportTasksState(verify=verify_tasks, release=release_tasks)


def is_release_eligible(version, target_minors, verify_statuses):
    """Checks if a release version is eligible based on verification statuses."""
    version_minor = ".".join(version.split(".")[:2])
    v_minor_parsed = [int(x) for x in version_minor.split(".")]

    for minor in target_minors:
        minor_parsed = [int(x) for x in minor.split(".")]
        if minor_parsed >= v_minor_parsed:
            status = verify_statuses.get(minor)
            if status != "success":
                return (
                    False,
                    f"Blocked by verification failure on {minor} (status: {status})",
                )

    return True, "Eligible"


def _load_release_template() -> str:
    """Loads the release tracking issue template."""
    template_path = pathlib.Path(".github/ISSUE_TEMPLATE/release_tracking_template.md")
    if not template_path.exists():
        raise FileNotFoundError(f"Template file not found at {template_path}")
    return template_path.read_text(encoding="utf-8")


class BackportCreateReleases:
    """Class to initiate releases for verified backports."""

    def __init__(self, args, gh: GitHub):
        self._args = args
        self._gh = gh

    def run(self) -> int:
        """Executes the backport-create-releases subcommand."""
        args = self._args
        issue_num = args.issue
        if not issue_num:
            raise ValueError("--issue is required.")

        print(f"Reading backport issue #{issue_num}...")
        body = self._gh.get_issue_body(issue_num)
        try:
            metadata = parse_backport_metadata(body)
        except ValueError as e:
            e.add_note(f"Failed to parse backport metadata from issue #{issue_num}")
            raise
        pr_ref = metadata.pr

        pr_num = self._gh.resolve_pr_number(pr_ref)

        # Parse tasks
        tasks_state = parse_backport_tasks(body)
        verify_statuses = tasks_state.verify
        release_tasks = tasks_state.release

        target_minors = sorted(
            list(verify_statuses.keys()), key=lambda m: [int(x) for x in m.split(".")]
        )

        # We need the templates for release issues
        template_content = _load_release_template()

        updated_body = body
        changes_made = False

        for version, (status, release_issue) in release_tasks.items():
            # If status is success, we already created the issue.
            # We check the actual checklist item status, but the helper returns it.
            # The status in metadata is 'success' when done.
            if status == "success":
                print(f"Release for {version} already initiated: {release_issue}")
                continue

            eligible, reason = is_release_eligible(
                version, target_minors, verify_statuses
            )

            task_name = f"Track Release {version}"

            if eligible:
                print(f"Initiating release for {version}...")

                # Check if release issue already exists
                existing_issues = self._gh.get_open_tracking_issues(version)
                if existing_issues:
                    new_issue_num = existing_issues[0]["number"]
                    print(
                        f"Release issue for {version} already exists: #{new_issue_num}. Reusing it."
                    )
                else:
                    # Create the issue
                    is_first_release = version.endswith(".0")
                    if is_first_release:
                        issue_template = template_content
                    else:
                        lines = template_content.splitlines()
                        lines = [
                            line for line in lines if not re.search(r"Tag RC\d+", line)
                        ]
                        issue_template = "\n".join(lines)
                        if template_content.endswith("\n"):
                            issue_template += "\n"

                    if args.dry_run:
                        print(
                            f"[DRY RUN] Would create release tracking issue for {version} (without RC tasks)"
                        )
                        new_issue_num = "<NEW_ISSUE_NUM>"
                    else:
                        new_issue_num = self._gh.create_release_tracking_issue(
                            version, issue_template
                        )
                        print(
                            f"Created release tracking issue #{new_issue_num} for {version}"
                        )

                        # Add the backport PR to the new release issue
                        print(
                            f"Adding PR #{pr_num} to release issue #{new_issue_num} checklist..."
                        )
                        rel_body = self._gh.get_issue_body(new_issue_num)
                        rel_body = add_backports_to_body(
                            rel_body, [{"ref": f"#{pr_num}"}]
                        )
                        rel_body = add_sync_changelog_task_to_body(rel_body, pr_num)
                        self._gh.update_issue_body(new_issue_num, rel_body)

                # Update task in backport issue
                metadata = {"status": "success", "release_issue": f"#{new_issue_num}"}
                updated_body = update_task_in_body(
                    updated_body, task_name, checked=True, metadata=metadata
                )
                changes_made = True
            else:
                print(f"Release for {version} is not eligible: {reason}")
                metadata = {"status": "error-later-release-did-not-apply"}

                if status != "error-later-release-did-not-apply":
                    updated_body = update_task_in_body(
                        updated_body, task_name, checked=False, metadata=metadata
                    )
                    changes_made = True

        if changes_made:
            if args.dry_run:
                print(
                    f"[DRY RUN] Would update backport issue #{issue_num} body:\n{updated_body}"
                )
            else:
                self._gh.update_issue_body(issue_num, updated_body)
                print(f"Updated backport issue #{issue_num}")
        else:
            print("No changes needed for backport issue.")

        return 0

    @classmethod
    def add_parser(cls, subparsers):
        """Adds parser for backport-create-releases subcommand."""
        parser = subparsers.add_parser(
            "backport-create-releases",
            help="Initiate releases for verified backports.",
        )
        parser.add_argument(
            "--issue",
            type=int,
            required=True,
            help="The backport tracking issue number (required).",
        )
        parser.add_argument(
            "--dry-run",
            action=argparse.BooleanOptionalAction,
            default=True,
            help="Perform a dry run (default: True). Use --no-dry-run to actually execute.",
        )
        parser.set_defaults(command=cls.run_from_args)

    @classmethod
    def run_from_args(cls, args):
        """Instantiates and runs the command from parsed args."""
        gh = GitHub()
        return cls(args, gh).run()

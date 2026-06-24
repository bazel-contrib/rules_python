"""A tool to perform release steps."""

import argparse
import datetime
import fnmatch
import os
import pathlib
import re
import sys

from packaging.version import parse as parse_version

from tools.private.release import gh, git

_REPO_URL = "https://github.com/bazel-contrib/rules_python"

_EXCLUDE_PATTERNS = [
    "./.git/*",
    "./.github/*",
    "./.bazelci/*",
    "./.bcr/*",
    "./bazel-*/*",
    "./CONTRIBUTING.md",
    "./RELEASING.md",
    "./tools/private/release/*",
    "./tests/tools/private/release/*",
]

_RELEASE_TITLE_RE = re.compile(r"Release\s+(\d+\.\d+\.\d+)", re.IGNORECASE)


def _iter_version_placeholder_files():
    for root, dirs, files in os.walk(".", topdown=True):
        # Filter directories
        dirs[:] = [
            d
            for d in dirs
            if not any(
                fnmatch.fnmatch(os.path.join(root, d), pattern)
                for pattern in _EXCLUDE_PATTERNS
            )
        ]

        for filename in files:
            filepath = os.path.join(root, filename)
            if any(fnmatch.fnmatch(filepath, pattern) for pattern in _EXCLUDE_PATTERNS):
                continue

            yield filepath


def get_latest_version():
    """Gets the latest version from git tags."""
    tags = git.get_tags()
    versions = [
        (tag, parse_version(tag))
        for tag in tags
        if re.match(r"^\d+\.\d+\.\d+(rc\d+)?$", tag.strip())
    ]
    if not versions:
        raise RuntimeError("No git tags found matching X.Y.Z or X.Y.ZrcN format.")

    versions.sort(key=lambda v: v[1])
    latest_tag, latest_version = versions[-1]

    if latest_version.is_prerelease:
        raise ValueError(f"The latest version is a pre-release version: {latest_tag}")

    stable_versions = [tag for tag, version in versions if not version.is_prerelease]
    if not stable_versions:
        raise ValueError("No stable git tags found matching X.Y.Z format.")

    return stable_versions[-1]


def get_latest_rc_tag(version):
    """Queries git tags and returns the highest RC tag for the version."""
    tags = git.get_tags()
    pattern = rf"^v{re.escape(version)}-rc\d+$"
    rc_tags = [tag.strip() for tag in tags if re.match(pattern, tag.strip())]
    if not rc_tags:
        return None
    rc_tags.sort(key=parse_version)
    return rc_tags[-1]


def should_increment_minor():
    """Checks if the minor version should be incremented."""
    for filepath in _iter_version_placeholder_files():
        try:
            with open(filepath, "r") as f:
                content = f.read()
        except (IOError, UnicodeDecodeError):
            continue

        if "VERSION_NEXT_FEATURE" in content:
            return True
    return False


def determine_next_version(branch_name=None):
    """Determines the next version based on git tags and the current branch."""
    if branch_name is None:
        branch_name = git.get_current_branch()

    if branch_name:
        release_match = re.match(r"^release/(\d+)\.(\d+)$", branch_name)
        if release_match:
            branch_major = int(release_match.group(1))
            branch_minor = int(release_match.group(2))
            print(
                f"Detected release branch: {branch_name} (targeting"
                f" {branch_major}.{branch_minor}.x)"
            )

            tags = git.get_tags()
            matching_patches = []
            for tag in tags:
                tag = tag.strip()
                m = re.match(rf"^{branch_major}\.{branch_minor}\.(\d+)$", tag)
                if m:
                    matching_patches.append(int(m.group(1)))

            if matching_patches:
                latest_patch = max(matching_patches)
                next_version = f"{branch_major}.{branch_minor}.{latest_patch + 1}"
                print(
                    f"Latest tag on this branch is"
                    f" {branch_major}.{branch_minor}.{latest_patch}. Next"
                    f" version: {next_version}"
                )
                return next_version
            else:
                next_version = f"{branch_major}.{branch_minor}.0"
                print(
                    f"No stable tags found for {branch_major}.{branch_minor}.x."
                    f" Next version: {next_version}"
                )
                return next_version

    latest_version = get_latest_version()
    major, minor, patch = [int(n) for n in latest_version.split(".")]

    if should_increment_minor():
        return f"{major}.{minor + 1}.0"
    else:
        return f"{major}.{minor}.{patch + 1}"


def _get_sub_category(content):
    """Extracts the sub-category in parentheses from the entry content."""
    match = re.match(r"^(?:\*|-)\s*\(([^)]+)\)", content)
    if match:
        return match.group(1).lower()
    return ""


def _get_news_files(news_dir):
    """Returns a list of news files matching the <id>.<category>.md pattern."""
    news_path = pathlib.Path(news_dir)
    if not news_path.exists():
        return []

    valid_files = []
    for p in news_path.iterdir():
        if not p.is_file():
            continue
        if p.suffix != ".md":
            continue
        parts = p.name.split(".")
        if len(parts) < 3:
            continue
        valid_files.append(p)

    return valid_files


def _parse_new_files(news_files):
    """Parses news files and groups them by category."""
    entries = {}
    for p in news_files:
        parts = p.name.split(".")
        category = parts[1].lower()

        content = p.read_text(encoding="utf-8").strip()

        if not content:
            continue

        if not (content.startswith("* ") or content.startswith("- ")):
            content = f"* {content}"

        if category not in entries:
            entries[category] = []
        entries[category].append(content)

    return entries


def generate_release_block(version, release_date, news_entries):
    """Generates the markdown block for the release."""
    header_version = version.replace(".", "-")
    lines = [
        f"{{#v{header_version}}}",
        f"## [{version}] - {release_date}",
        "",
        f"[{version}]: https://github.com/bazel-contrib/rules_python/releases/tag/{version}",
        "",
    ]

    category_order = ["removed", "changed", "fixed", "added"]
    for cat in news_entries:
        if cat not in category_order:
            category_order.append(cat)

    for cat in category_order:
        if cat in news_entries and news_entries[cat]:
            lines.append(f"{{#v{header_version}-{cat}}}")
            lines.append(f"### {cat.capitalize()}")

            sorted_entries = sorted(
                news_entries[cat], key=lambda e: (_get_sub_category(e), e)
            )

            for entry in sorted_entries:
                lines.append(entry)
            lines.append("")

    return "\n".join(lines)


def _add_news_to_changelog(changelog_path, version, entries, release_date):
    """Adds or merges news entries into CHANGELOG.md."""
    changelog_path_obj = pathlib.Path(changelog_path)
    changelog_content = changelog_path_obj.read_text(encoding="utf-8")

    header_version = version.replace(".", "-")
    version_anchor = f"{{#v{header_version}}}"
    version_exists = version_anchor in changelog_content

    if version_exists:
        if not entries:
            print(
                f"Version {version} already exists and no news entries found"
                " to merge. Doing nothing."
            )
            return

        print(f"Version {version} already exists in changelog. Merging news entries...")
        pattern = (
            r"(?P<anchor>\{#v"
            + re.escape(header_version)
            + r"\})(?P<content>.*?)(?=\n\s*\{#v(?!0-0-0)\d+-\d+-\d+\}|\Z)"
        )
        match = re.search(pattern, changelog_content, re.DOTALL)
        if not match:
            raise RuntimeError(
                f"Could not find content for existing version {version} in CHANGELOG.md"
            )

        content_block = match.group("content")

        category_anchor_pattern = (
            r"\{#v" + re.escape(header_version) + r"-(?P<cat>[a-z]+)\}"
        )
        match_cat = re.search(category_anchor_pattern, content_block)
        if match_cat:
            header_end_idx = match_cat.start()
            header_str = content_block[:header_end_idx]
            categories_str = content_block[header_end_idx:]
        else:
            header_str = content_block
            categories_str = ""

        existing_entries = {}
        if categories_str:
            cat_matches = list(re.finditer(category_anchor_pattern, categories_str))
            for i, m in enumerate(cat_matches):
                cat = m.group("cat")
                start_idx = m.end()
                end_idx = (
                    cat_matches[i + 1].start()
                    if i + 1 < len(cat_matches)
                    else len(categories_str)
                )
                cat_content = categories_str[start_idx:end_idx].strip()

                lines = cat_content.splitlines()
                cat_entries = []
                current_entry = []
                for line in lines:
                    if not line.strip() or line.strip().startswith("### "):
                        continue
                    if line.startswith("* ") or line.startswith("- "):
                        if current_entry:
                            cat_entries.append("\n".join(current_entry))
                        current_entry = [line]
                    else:
                        if current_entry:
                            current_entry.append(line)
                if current_entry:
                    cat_entries.append("\n".join(current_entry))
                existing_entries[cat] = cat_entries

        merged_entries = dict(existing_entries)
        for cat, cat_entries in entries.items():
            if cat not in merged_entries:
                merged_entries[cat] = []
            merged_entries[cat].extend(cat_entries)

        reconstructed_lines = []
        category_order = ["removed", "changed", "fixed", "added"]
        for cat in merged_entries:
            if cat not in category_order:
                category_order.append(cat)

        for cat in category_order:
            if cat in merged_entries and merged_entries[cat]:
                reconstructed_lines.append(f"{{#v{header_version}-{cat}}}")
                reconstructed_lines.append(f"### {cat.capitalize()}")

                sorted_entries = sorted(
                    merged_entries[cat], key=lambda e: (_get_sub_category(e), e)
                )

                for entry in sorted_entries:
                    reconstructed_lines.append(entry)
                reconstructed_lines.append("")

        new_categories_str = "\n".join(reconstructed_lines)
        new_release_block = (
            header_str.rstrip() + "\n\n" + new_categories_str.strip() + "\n"
        )

        new_content = re.sub(
            pattern,
            r"\g<anchor>\n" + new_release_block.strip() + "\n",
            changelog_content,
            flags=re.DOTALL,
        )
        changelog_path_obj.write_text(new_content, encoding="utf-8")

    else:
        if entries:
            print(
                f"Version {version} does not exist in changelog. Creating new"
                " release section from news entries..."
            )
            template_match = re.search(
                r"BEGIN_UNRELEASED_TEMPLATE\s*\n(.*?)\n\s*END_UNRELEASED_TEMPLATE",
                changelog_content,
                re.DOTALL,
            )
            if not template_match:
                raise RuntimeError(
                    "Could not find BEGIN_UNRELEASED_TEMPLATE in CHANGELOG.md"
                )

            unreleased_template = template_match.group(1).strip()
            new_release_block = generate_release_block(version, release_date, entries)

            replacement = f"{unreleased_template}\n\n{new_release_block}\n"

            pattern = r"(END_UNRELEASED_TEMPLATE\s*\n-->\s*\n)(.*?)(\n\s*\{#v(?!0-0-0)\d+-\d+-\d+\})"

            if not re.search(pattern, changelog_content, re.DOTALL):
                raise RuntimeError(
                    "Could not find active Unreleased section to replace in"
                    " CHANGELOG.md"
                )

            new_content = re.sub(
                pattern,
                r"\g<1>" + replacement + r"\g<3>",
                changelog_content,
                flags=re.DOTALL,
            )
            changelog_path_obj.write_text(new_content, encoding="utf-8")
        else:
            print(
                f"No news entries found and version {version} does not exist."
                " Falling back to manual changelog update..."
            )
            header_version = version.replace(".", "-")
            lines = changelog_content.splitlines()

            new_lines = []
            after_template = False
            before_already_released = True
            for line in lines:
                if "END_UNRELEASED_TEMPLATE" in line:
                    after_template = True
                if re.match("#v[1-9]-", line):
                    before_already_released = False

                if after_template and before_already_released:
                    line = line.replace(
                        "## Unreleased", f"## [{version}] - {release_date}"
                    )
                    line = line.replace("v0-0-0", f"v{header_version}")
                    line = line.replace("0.0.0", version)

                new_lines.append(line)

            changelog_path_obj.write_text("\n".join(new_lines), encoding="utf-8")


def update_changelog(
    version, release_date, changelog_path="CHANGELOG.md", news_dir="news"
):
    """Performs the version replacements in CHANGELOG.md."""
    news_files = _get_news_files(news_dir)
    entries = _parse_new_files(news_files)

    _add_news_to_changelog(changelog_path, version, entries, release_date)

    for p in news_files:
        p.unlink()
    if news_files:
        print(f"Removed {len(news_files)} processed news files.")


def replace_version_next(version):
    """Replaces all VERSION_NEXT_* placeholders with the new version."""
    for filepath in _iter_version_placeholder_files():
        try:
            with open(filepath, "r") as f:
                content = f.read()
        except (IOError, UnicodeDecodeError):
            continue

        if "VERSION_NEXT_FEATURE" in content or "VERSION_NEXT_PATCH" in content:
            new_content = content.replace("VERSION_NEXT_FEATURE", version)
            new_content = new_content.replace("VERSION_NEXT_PATCH", version)
            with open(filepath, "w") as f:
                f.write(new_content)


def _semver_type(value):
    if not re.match(r"^\d+\.\d+\.\d+(rc\d+)?$", value):
        raise argparse.ArgumentTypeError(
            f"'{value}' is not a valid semantic version (X.Y.Z or X.Y.ZrcN)"
        )
    return value


# ==============================================================================
# Checklist Parser and Formatter (Using new | key=value syntax)
# ==============================================================================


def parse_metadata_line(line):
    """Parses a checklist line with optional | key=value metadata."""
    match = re.match(r"^\s*-\s*\[([ xX])\]\s+([^|]+)(?:\s*\|\s*(.*))?$", line)
    if not match:
        return None

    checked = match.group(1).lower() == "x"
    name = match.group(2).strip()
    metadata_str = match.group(3)

    metadata = {}
    if metadata_str:
        pairs = metadata_str.strip().split()
        for pair in pairs:
            if "=" in pair:
                k, v = pair.split("=", 1)
                metadata[k] = v

    return {
        "checked": checked,
        "name": name,
        "metadata": metadata,
        "original_line": line,
    }


def format_metadata_line(checked, name, metadata):
    """Formats a checklist line with space-separated key=value metadata."""
    check_str = "x" if checked else " "
    if not metadata:
        return f"- [{check_str}] {name}"

    metadata_str = " ".join(f"{k}={v}" for k, v in metadata.items())
    return f"- [{check_str}] {name} | {metadata_str}"


def update_task_in_body(body, task_name, checked, metadata):
    """Updates a specific task's checked state and metadata in the issue body."""
    lines = body.splitlines()
    updated_lines = []
    found = False

    for line in lines:
        parsed = parse_metadata_line(line)
        if parsed and parsed["name"].lower() == task_name.lower():
            updated_lines.append(format_metadata_line(checked, task_name, metadata))
            found = True
        else:
            updated_lines.append(line)

    if not found:
        raise ValueError(f"Task '{task_name}' not found in issue body.")

    return "\n".join(updated_lines)


def parse_checklist_state(body):
    """Parses the main checklist tasks and their metadata."""
    state = {
        "prepare_release": {
            "checked": False,
            "status": None,
            "pr": None,
            "commit": None,
        },
        "create_branch": {
            "checked": False,
            "status": None,
            "branch": None,
            "commit": None,
        },
        "tag_final": {"checked": False, "status": None, "tag": None, "commit": None},
        "rc_tags": {},  # Dynamically mapped: int -> metadata dict
    }

    lines = body.splitlines()
    for line in lines:
        parsed = parse_metadata_line(line)
        if not parsed:
            continue

        name = parsed["name"].strip()
        meta = parsed["metadata"]
        checked = parsed["checked"]
        name_lower = name.lower()

        if "prepare release" in name_lower:
            state["prepare_release"] = {
                "checked": checked,
                "status": meta.get("status"),
                "pr": meta.get("pr"),
                "commit": meta.get("commit"),
            }
        elif "create release branch" in name_lower:
            state["create_branch"] = {
                "checked": checked,
                "status": meta.get("status"),
                "branch": meta.get("branch"),
                "commit": meta.get("commit"),
            }
        elif "tag final" in name_lower:
            state["tag_final"] = {
                "checked": checked,
                "status": meta.get("status"),
                "tag": meta.get("tag"),
                "commit": meta.get("commit"),
            }
        else:
            # Match Tag RC<num>
            rc_match = re.match(r"Tag RC(\d+)", name, re.IGNORECASE)
            if rc_match:
                rc_num = int(rc_match.group(1))
                state["rc_tags"][rc_num] = {
                    "checked": checked,
                    "status": meta.get("status"),
                    "tag": meta.get("tag"),
                    "commit": meta.get("commit"),
                }

    return state


def parse_backports(body):
    """Parses the ## Backports checklist section."""
    body = body.replace("\r\n", "\n")
    match = re.search(
        r"## Backports\n(.*?)(?=\n##|\n---|\Z)", body, re.DOTALL | re.IGNORECASE
    )
    if not match:
        return []

    section_content = match.group(1)
    items = []
    lines = section_content.splitlines()

    for line in lines:
        parsed = parse_metadata_line(line)
        if parsed:
            items.append(
                {
                    "pr_ref": parsed["name"],
                    "checked": parsed["checked"],
                    "status": parsed["metadata"].get("status", "PENDING"),
                    "rc": parsed["metadata"].get("rc"),
                    "commit": parsed["metadata"].get("commit"),
                    "metadata": parsed["metadata"],
                }
            )
    return items


# ==============================================================================
# Subcommand Execution Functions
# ==============================================================================


def cmd_determine_next_version(args):
    """Executes the determine-next-version subcommand."""
    version = determine_next_version()
    print(version)
    return 0


def cmd_create_release_issue(args):
    """Executes the create-release-issue subcommand."""
    version = args.version
    if version is None:
        version = determine_next_version()

    # Concurrency check
    open_issues = gh.get_open_tracking_issues()
    if open_issues:
        print("Error: A release is already in progress. Active tracking issues:")
        for issue in open_issues:
            print(f"- {issue['title']}: {issue['url']}")
        return 1

    template_path = pathlib.Path(".github/ISSUE_TEMPLATE/release_tracking_template.md")
    if not template_path.exists():
        raise FileNotFoundError(f"Template file not found at {template_path}")
    template_content = template_path.read_text(encoding="utf-8")

    issue_num = gh.create_tracking_issue(version, template_content)
    print(f"Created tracking issue #{issue_num} for v{version}")
    return 0


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

    print(f"Running preparation pipeline for v{version}...")

    branch_name = f"prepare-{version}"
    if git.branch_exists(branch_name):
        print(f"Branch {branch_name} already exists. Checking it out...")
        git.checkout(branch_name)
    else:
        git.checkout(branch_name, create_branch=True)

    print("Updating changelog and placeholders...")
    release_date = datetime.date.today().strftime("%Y-%m-%d")
    update_changelog(version, release_date)
    replace_version_next(version)

    modified_files = git.status()
    if not modified_files:
        print("No files modified by the release tool. Nothing to commit.")
        return 0

    # Stage only modified files
    for line in modified_files.splitlines():
        file_path = line.strip().split()[-1]
        git.add(file_path)

    git.commit(f"Prepare release {version}")
    git.push("origin", branch_name)

    issue_num = args.issue
    if not issue_num:
        open_issues = gh.get_open_tracking_issues()
        for issue in open_issues:
            if f"Release {version}" in issue["title"]:
                issue_num = issue["number"]
                break

        if not issue_num:
            print(
                f"No active tracking issue found for v{version}. Creating a new one..."
            )
            template_path = pathlib.Path(
                ".github/ISSUE_TEMPLATE/release_tracking_template.md"
            )
            if not template_path.exists():
                raise FileNotFoundError(f"Template file not found at {template_path}")
            template_content = template_path.read_text(encoding="utf-8")
            issue_num = gh.create_tracking_issue(version, template_content)

    print(f"Using tracking issue #{issue_num}")

    pr_url = gh.create_pr(version, branch_name, issue_num)
    pr_num = pr_url.split("/")[-1]
    print(f"Created Pull Request: {pr_url} (PR #{pr_num})")

    print(f"Updating tracking issue #{issue_num} checklist status to PENDING...")
    body = gh.get_issue_body(issue_num)
    metadata = {"status": "pending", "pr": f"#{pr_num}"}
    updated_body = update_task_in_body(
        body, "Prepare Release", checked=False, metadata=metadata
    )
    gh.update_issue_body(issue_num, updated_body)
    print("Preparation pipeline completed successfully!")
    return 0


def cmd_complete_prepare(args):
    """Executes the complete-prepare subcommand (Phase 2 PR merged)."""
    print(f"Completing preparation for PR #{args.pr}...")

    pr_info = gh.get_pr_info(args.pr)
    if not pr_info or pr_info.get("state") != "MERGED":
        state = pr_info.get("state", "UNKNOWN")
        print(f"Error: PR #{args.pr} is not merged yet (state: {state}).")
        return 1

    # Resolve issue number from PR body
    pr_body = pr_info.get("body", "")
    match = re.search(r"Work towards #(\d+)", pr_body)
    if not match:
        match = re.search(r"#(\d+)", pr_body)
    if not match:
        print(
            f"Error: Could not determine tracking issue number from PR #{args.pr}"
            f" body: {pr_body}"
        )
        return 1

    issue_num = int(match.group(1))
    print(f"Resolved tracking issue #{issue_num} from PR #{args.pr} body.")

    commit_sha = pr_info["mergeCommit"]["oid"]
    short_commit = commit_sha[:8]
    print(f"PR #{args.pr} merged at commit {commit_sha}. Updating tracking issue...")

    # Update checklist: mark Prepare Release as done (checked) and set SUCCESS
    body = gh.get_issue_body(issue_num)
    metadata = {"status": "done", "pr": f"#{args.pr}", "commit": short_commit}
    updated_body = update_task_in_body(
        body, "Prepare Release", checked=True, metadata=metadata
    )
    gh.update_issue_body(issue_num, updated_body)
    print("Prepare Release task marked complete successfully!")
    return 0


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
    version_match = _RELEASE_TITLE_RE.search(issue_title)
    if not version_match:
        print(f"Error: Could not parse version from issue title: {issue_title}")
        return 1

    version = version_match.group(1)
    branch_version = ".".join(version.split(".")[:2])
    branch_name = f"release/{branch_version}"

    commit_sha = state["prepare_release"]["commit"]
    print(f"Cutting branch {branch_name} from commit {commit_sha}...")

    # Create and push branch
    git.fetch("origin")
    git.checkout(commit_sha)

    if not git.branch_exists(branch_name):
        git.checkout(branch_name, create_branch=True)
    else:
        git.checkout(branch_name)
        git.merge(commit_sha, ff_only=True)

    git.push("origin", branch_name)
    print(f"Successfully pushed branch {branch_name}")

    # Update tracking issue checklist
    print("Updating tracking issue checklist...")
    metadata = {"status": "done", "branch": branch_name, "commit": commit_sha[:8]}
    updated_body = update_task_in_body(
        body, "Create Release branch", checked=True, metadata=metadata
    )
    gh.update_issue_body(args.issue, updated_body)
    print("Create Release branch task marked complete successfully!")
    return 0


def cmd_process_backports(args):
    """Executes the process-backports subcommand."""
    body = gh.get_issue_body(args.issue)
    items = parse_backports(body)

    pending_items = [
        item
        for item in items
        if not item["checked"] and item["status"] != "merge-conflict"
    ]

    if not pending_items:
        print("No pending backports found.")
        return 0

    print(f"Found {len(pending_items)} pending backports to process.")

    # Determine branch name from issue title
    issue_title = gh.get_issue_title(args.issue)
    version_match = _RELEASE_TITLE_RE.search(issue_title)
    if not version_match:
        print(f"Error: Could not parse version from issue title: {issue_title}")
        return 1

    version = version_match.group(1)
    branch_version = ".".join(version.split(".")[:2])
    branch_name = f"release/{branch_version}"

    # Determine next RC tag to write to backport metadata
    git.fetch("--tags", "--force")
    latest_rc = get_latest_rc_tag(version)
    if not latest_rc:
        next_rc_suffix = "rc0"
    else:
        rc_num = int(latest_rc.split("-rc")[-1])
        next_rc_suffix = f"rc{rc_num + 1}"

    # Resolve PRs to merge commits using gh helper
    resolved_items = gh.resolve_backport_commits(pending_items)

    shas = []
    sha_to_item = {}
    any_failed = False
    for item in resolved_items:
        if item.get("commit"):
            sha = item["commit"]
            sha_to_item[sha] = item
            shas.append(sha)
        else:
            any_failed = True
            body = update_task_in_body(
                body,
                item["pr_ref"],
                checked=False,
                metadata={"status": item.get("status", "failed")},
            )
            gh.update_issue_body(args.issue, body)

    if not shas:
        print("No valid merge commits to process.")
        if any_failed:
            return 1
        return 0

    # Sort chronologically using git helper
    sorted_shas = git.sort_commits_chronologically(shas)

    git.fetch("origin")
    git.checkout(branch_name)

    for sha in sorted_shas:
        item = sha_to_item[sha]
        print(f"Cherry-picking {sha} (PR {item['pr_ref']})...")
        try:
            git.cherry_pick(sha)

            # Perform news processing (merging news/ files into the changelog)
            print(f"Merging news fragments into changelog for PR {item['pr_ref']}...")
            release_date = datetime.date.today().strftime("%Y-%m-%d")
            update_changelog(version, release_date)

            # Stage changelog changes and news/ deletions
            git.add("CHANGELOG.md", "news/")

            # Amend cherry-pick commit to include news merging and deletions
            print(f"Amending cherry-pick commit for PR {item['pr_ref']}...")
            git.commit("", amend=True, no_edit=True)

            # Push amended commit
            git.push("origin", branch_name)

            new_sha = git.get_commit_sha("HEAD", short=True)
            metadata = {"status": "done", "rc": next_rc_suffix, "commit": new_sha}
            body = update_task_in_body(
                body, item["pr_ref"], checked=True, metadata=metadata
            )
            gh.update_issue_body(args.issue, body)
            print(f"Applied: SUCCESS {new_sha}")
        except Exception as e:
            print(f"Conflict or error on {sha}: {e}. Aborting.")
            try:
                git.cherry_pick_abort()
            except Exception:
                pass
            any_failed = True

            body = update_task_in_body(
                body,
                item["pr_ref"],
                checked=False,
                metadata={"status": "merge-conflict"},
            )
            gh.update_issue_body(args.issue, body)
            print("Updated backport item to status=merge-conflict (unchecked)")

    if any_failed:
        print("One or more cherry-picks/resolutions failed.")
        return 1
    print("All backports successfully processed!")
    return 0


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
    version_match = _RELEASE_TITLE_RE.search(issue_title)
    if not version_match:
        print(f"Error: Could not parse version from issue title: {issue_title}")
        return 1

    version = version_match.group(1)
    branch_version = ".".join(version.split(".")[:2])
    branch_name = f"release/{branch_version}"

    # Determine next RC tag
    git.fetch("--tags", "--force")
    latest_rc = get_latest_rc_tag(version)

    if not latest_rc:
        next_rc_num = 0
        next_rc = f"v{version}-rc0"
    else:
        rc_num = int(latest_rc.split("-rc")[-1])
        next_rc_num = rc_num + 1
        next_rc = f"v{version}-rc{next_rc_num}"

    # Precheck: next RC number must exist and be unchecked in the checklist
    rc_tags = state.get("rc_tags", {})
    if next_rc_num not in rc_tags:
        print(
            f"Error: Checklist is missing required task 'Tag RC{next_rc_num}'"
            f" to cut v{version}-rc{next_rc_num}."
        )
        return 1

    target_rc_task = rc_tags[next_rc_num]
    if target_rc_task["checked"] or target_rc_task["status"] == "done":
        print(
            f"Error: Task 'Tag RC{next_rc_num}' is already marked done in the checklist."
        )
        return 1

    # Verify HEAD is not already tagged
    git.checkout(branch_name)
    head_tags = git.get_tags_at_head()
    if any(tag.startswith(f"v{version}-rc") for tag in head_tags):
        print(f"HEAD of {branch_name} is already tagged with an RC. Skipping.")
        return 0

    print(f"Tagging and pushing next RC: {next_rc}...")
    git.tag(next_rc)
    git.push("origin", next_rc)

    commit_sha = git.get_commit_sha("HEAD")

    # Check off the appropriate "Tag RC{N}" task in the checklist
    print(f"Checking off Tag RC{next_rc_num} task...")
    metadata = {"status": "done", "tag": next_rc, "commit": commit_sha[:8]}
    task_name = f"Tag RC{next_rc_num}"
    updated_body = update_task_in_body(body, task_name, checked=True, metadata=metadata)
    gh.update_issue_body(args.issue, updated_body)

    tag_url = f"{_REPO_URL}/releases/tag/{next_rc}"
    bcr_search_url = f"https://github.com/bazelbuild/bazel-central-registry/pulls?q=is%3Apr+rules_python+{version}"
    comment_body = f"""🚀 **New Release Candidate Tagged!**

Release Candidate **{next_rc}** has been successfully generated and tagged on branch `{branch_name}`.

View Tag: [{next_rc}]({tag_url})
Track BCR Progress: [Search BCR Pull Requests]({bcr_search_url})"""
    gh.post_issue_comment(args.issue, comment_body)
    print("RC creation completed successfully!")
    return 0


def cmd_promote_rc(args):
    """Executes the promote-rc subcommand (Phase 3)."""
    version = args.version
    if version is None:
        version = determine_next_version()
    version = version.replace("v", "")
    final_tag = f"v{version}"

    git.fetch("--tags", "--force")
    latest_rc = get_latest_rc_tag(version)
    if not latest_rc:
        print(f"Error: No release candidate tags found matching v{version}-rc*")
        return 1

    print(f"Promoting {latest_rc} to final release {final_tag}...")
    git.checkout(latest_rc)

    commit_sha = git.get_commit_sha("HEAD")

    if not git.tag_exists(final_tag):
        git.tag(final_tag)
        git.push("origin", final_tag)
    else:
        print(f"Final tag {final_tag} already exists.")

    # Resolve issue number
    issue_num = args.issue
    if not issue_num:
        try:
            issue_num = gh.resolve_issue_number(version)
        except Exception as e:
            print(f"Warning: Could not query GitHub to find tracking issue: {e}")

    if issue_num:
        print(f"Updating tracking issue #{issue_num} checklist...")
        body = gh.get_issue_body(issue_num)
        metadata = {"status": "done", "tag": final_tag, "commit": commit_sha[:8]}
        updated_body = update_task_in_body(
            body, "Tag Final", checked=True, metadata=metadata
        )
        gh.update_issue_body(issue_num, updated_body)
        print("Checklist updated successfully.")
        return 0
    else:
        print(
            "Error: No active tracking issue found or specified. Checklist was not updated."
        )
        return 1


def create_parser():
    """Creates the argument parser with subcommands."""
    parser = argparse.ArgumentParser(
        description="Automate release steps for rules_python."
    )

    subparsers = parser.add_subparsers(
        dest="command", required=True, help="Subcommands"
    )

    # Subcommand: determine-next-version
    subparsers.add_parser(
        "determine-next-version",
        help="Determine the next version and print it, without making any changes.",
    )

    # Subcommand: create-release-issue
    create_issue_parser = subparsers.add_parser(
        "create-release-issue",
        help="Search for open releases and create a new tracking issue.",
    )
    create_issue_parser.add_argument(
        "--version",
        type=_semver_type,
        help="The release version (e.g., 0.38.0). If not provided, determined automatically.",
    )

    # Subcommand: prepare
    prepare_parser = subparsers.add_parser(
        "prepare",
        help="Prepare the release (updates changelog, placeholders).",
    )
    prepare_parser.add_argument(
        "version",
        nargs="?",
        type=_semver_type,
        help="The new release version (e.g., 0.28.0). If not provided, "
        "it will be determined automatically.",
    )
    prepare_parser.add_argument(
        "--issue",
        type=int,
        help="The tracking issue number (optional, triggers automated branch/PR pipeline).",
    )

    # Subcommand: complete-prepare
    complete_prep_parser = subparsers.add_parser(
        "complete-prepare",
        help="Mark the Prepare Release task as complete in the tracking issue.",
    )
    complete_prep_parser.add_argument(
        "--pr",
        type=int,
        required=True,
        help="The merged preparation PR number.",
    )

    # Subcommand: create-release-branch
    create_branch_parser = subparsers.add_parser(
        "create-release-branch",
        help="Create the release branch pointing to the merged PR commit.",
    )
    create_branch_parser.add_argument(
        "--issue",
        type=int,
        required=True,
        help="The tracking issue number (required).",
    )

    # Subcommand: process-backports
    process_backports_parser = subparsers.add_parser(
        "process-backports",
        help="Cherry-pick pending backports listed in the tracking issue.",
    )
    process_backports_parser.add_argument(
        "--issue",
        type=int,
        required=True,
        help="The tracking issue number (required).",
    )

    # Subcommand: create-rc
    create_rc_parser = subparsers.add_parser(
        "create-rc",
        help="Tags the next RC on the release branch if no backports remain.",
    )
    create_rc_parser.add_argument(
        "--issue",
        type=int,
        required=True,
        help="The tracking issue number (required).",
    )

    # Subcommand: promote-rc
    promote_parser = subparsers.add_parser(
        "promote-rc",
        help="Promote the latest RC to final release.",
    )
    promote_parser.add_argument(
        "version",
        nargs="?",
        type=_semver_type,
        help="The final version to release (e.g., 0.38.0).",
    )
    promote_parser.add_argument(
        "--issue",
        type=int,
        help="The tracking issue number (optional).",
    )

    return parser


def main():
    if "BUILD_WORKSPACE_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKSPACE_DIRECTORY"])

    parser = create_parser()
    args = parser.parse_args()

    exit_code = 1
    try:
        if args.command == "determine-next-version":
            exit_code = cmd_determine_next_version(args)
        elif args.command == "create-release-issue":
            exit_code = cmd_create_release_issue(args)
        elif args.command == "prepare":
            exit_code = cmd_prepare(args)
        elif args.command == "complete-prepare":
            exit_code = cmd_complete_prepare(args)
        elif args.command == "create-release-branch":
            exit_code = cmd_create_release_branch(args)
        elif args.command == "process-backports":
            exit_code = cmd_process_backports(args)
        elif args.command == "create-rc":
            exit_code = cmd_create_rc(args)
        elif args.command == "promote-rc":
            exit_code = cmd_promote_rc(args)
    except Exception as e:
        print(f"Fatal error executing {args.command}: {e}", file=sys.stderr)
        sys.exit(1)

    sys.exit(exit_code if exit_code is not None else 0)


if __name__ == "__main__":
    main()

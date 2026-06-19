"""A tool to perform release steps."""

import argparse
import datetime
import fnmatch
import os
import pathlib
import re
import subprocess

from packaging.version import parse as parse_version

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


def _get_git_tags():
    """Runs a git command and returns the output."""
    return subprocess.check_output(["git", "tag"]).decode("utf-8").splitlines()


def get_latest_version():
    """Gets the latest version from git tags."""
    tags = _get_git_tags()
    # The packaging module can parse PEP440 versions, including RCs.
    # It has a good understanding of version precedence.
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

    # After all that, we only want to consider stable versions for the release.
    stable_versions = [tag for tag, version in versions if not version.is_prerelease]
    if not stable_versions:
        raise ValueError("No stable git tags found matching X.Y.Z format.")

    # The versions are already sorted, so the last one is the latest.
    return stable_versions[-1]


def should_increment_minor():
    """Checks if the minor version should be incremented."""
    for filepath in _iter_version_placeholder_files():
        try:
            with open(filepath, "r") as f:
                content = f.read()
        except (IOError, UnicodeDecodeError):
            # Ignore binary files or files with read errors
            continue

        if "VERSION_NEXT_FEATURE" in content:
            return True
    return False


def _get_current_branch():
    """Returns the current git branch name, or None if not in a git repo."""
    try:
        return (
            subprocess.check_output(
                ["git", "rev-parse", "--abbrev-ref", "HEAD"],
                stderr=subprocess.DEVNULL,
            )
            .decode("utf-8")
            .strip()
        )
    except subprocess.CalledProcessError:
        return None


def determine_next_version(branch_name=None):
    """Determines the next version based on git tags and the current branch."""
    if branch_name is None:
        branch_name = _get_current_branch()

    if branch_name:
        release_match = re.match(r"^release/(\d+)\.(\d+)$", branch_name)
        if release_match:
            branch_major = int(release_match.group(1))
            branch_minor = int(release_match.group(2))
            print(
                f"Detected release branch: {branch_name} (targeting"
                f" {branch_major}.{branch_minor}.x)"
            )

            # Find all stable tags matching this major.minor prefix.
            # Crucially, we ignore release candidates (RCs) here. If an RC is active
            # (e.g. 0.37.0-rc0 exists but 0.37.0 stable does not), we want to continue
            # targeting 0.37.0, NOT increment to 0.37.1.
            tags = _get_git_tags()
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
                # No stable tags exist yet for this release branch (preparing X.Y.0,
                # even if X.Y.0-rcN tags already exist)
                next_version = f"{branch_major}.{branch_minor}.0"
                print(
                    f"No stable tags found for {branch_major}.{branch_minor}.x."
                    f" Next version: {next_version}"
                )
                return next_version

    # Fallback to default behavior (for main branch or other development branches)
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

        # Format as list item if not already
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

    # Standard categories in preferred order
    category_order = ["removed", "changed", "fixed", "added"]
    # Add any other categories found
    for cat in news_entries:
        if cat not in category_order:
            category_order.append(cat)

    for cat in category_order:
        if cat in news_entries and news_entries[cat]:
            lines.append(f"{{#v{header_version}-{cat}}}")
            lines.append(f"### {cat.capitalize()}")

            # Sort entries by sub-category, then by content
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
        # Extract the existing version block
        # Match from the version anchor to the next version anchor (or end of file)
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

        # Split content_block into header and categories
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

        # Parse existing categories
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

        # Merge news entries
        merged_entries = dict(existing_entries)
        for cat, cat_entries in entries.items():
            if cat not in merged_entries:
                merged_entries[cat] = []
            merged_entries[cat].extend(cat_entries)

        # Reconstruct categories
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

        # Replace in changelog
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
            # Extract template
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

            # Replace the active Unreleased section
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
            # Fallback to old behavior
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

    # Delete news files after successful update
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
            # Ignore binary files or files with read errors
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


def create_parser():
    """Creates the argument parser."""
    parser = argparse.ArgumentParser(
        description="Automate release steps for rules_python."
    )
    parser.add_argument(
        "version",
        nargs="?",
        type=_semver_type,
        help="The new release version (e.g., 0.28.0). If not provided, "
        "it will be determined automatically.",
    )
    return parser


def main():
    # Change to the workspace root so the script can be run using `bazel run`
    if "BUILD_WORKSPACE_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKSPACE_DIRECTORY"])

    parser = create_parser()
    args = parser.parse_args()

    version = args.version
    if version is None:
        print("No version provided, determining next version automatically...")
        version = determine_next_version()
        print(f"Determined next version: {version}")

    print("Updating changelog ...")
    release_date = datetime.date.today().strftime("%Y-%m-%d")
    update_changelog(version, release_date)

    print("Replacing VERSION_NEXT placeholders ...")
    replace_version_next(version)

    print("Done")


if __name__ == "__main__":
    main()

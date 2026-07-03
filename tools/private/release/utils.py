"""Utility functions for the release tool."""

import argparse
import fnmatch
import os
import re

from packaging.version import parse as parse_version

from tools.private.release.git import Git

REPO_URL = "https://github.com/bazel-contrib/rules_python"


def semver_type(value):
    """Argparse type validator for semantic versions."""
    if not re.match(r"^\d+\.\d+\.\d+(rc\d+)?$", value):
        raise argparse.ArgumentTypeError(
            f"'{value}' is not a valid semantic version (X.Y.Z or X.Y.ZrcN)"
        )
    return value


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


def get_latest_version():
    """Gets the latest version from git tags."""
    git = Git(".")
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


def get_latest_rc_tag(version, remote=None):
    """Queries git tags and returns the highest RC tag for the version."""
    git = Git(".")
    if remote:
        tags = git.get_remote_tags(remote)
    else:
        tags = git.get_tags()
    pattern = rf"^{re.escape(version)}-rc\d+$"
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
    git = Git(".")
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


def parse_pr_list(value: str) -> list[int]:
    """Parses a comma or space separated list of PR numbers.

    PR numbers can optionally be prefixed with '#'.
    """
    if not value:
        return []
    # Split by space and/or comma
    pr_strings = [p for p in re.split(r"[\s,]+", value.strip()) if p]
    prs = []
    for pr_str in pr_strings:
        clean_pr_str = pr_str.lstrip("#")
        try:
            prs.append(int(clean_pr_str))
        except ValueError as e:
            raise argparse.ArgumentTypeError(
                f"Invalid PR reference '{pr_str}'. Must be integer optionally"
                f" prefixed with '#'."
            ) from e
    return prs

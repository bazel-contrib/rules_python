"""A tool to perform release steps."""

import argparse
import datetime
import fnmatch
import os
import re
import subprocess

from packaging.version import parse as parse_version

from tools.private.release import changelog_news

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
    changelog_news.update_changelog(version, release_date)

    print("Replacing VERSION_NEXT placeholders ...")
    replace_version_next(version)

    print("Done")


if __name__ == "__main__":
    main()

"""A tool to perform release steps."""

import argparse
import datetime
import fnmatch
import os
import pathlib
import re


def update_changelog(version, release_date, changelog_path="CHANGELOG.md"):
    """Performs the version replacements in CHANGELOG.md."""

    header_version = version.replace(".", "-")

    changelog_path_obj = pathlib.Path(changelog_path)
    lines = changelog_path_obj.read_text().splitlines()

    new_lines = []
    after_template = False
    before_already_released = True
    for line in lines:
        if "END_UNRELEASED_TEMPLATE" in line:
            after_template = True
        if re.match("#v[1-9]-", line):
            before_already_released = False

        if after_template and before_already_released:
            line = line.replace("## Unreleased", f"## [{version}] - {release_date}")
            line = line.replace("v0-0-0", f"v{header_version}")
            line = line.replace("0.0.0", version)

        new_lines.append(line)

    changelog_path_obj.write_text("\n".join(new_lines))


def replace_version_next(version):
    """Replaces all VERSION_NEXT_* placeholders with the new version."""
    exclude_patterns = [
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

    for root, dirs, files in os.walk(".", topdown=True):
        # Filter directories
        dirs[:] = [
            d
            for d in dirs
            if not any(
                fnmatch.fnmatch(os.path.join(root, d), pattern)
                for pattern in exclude_patterns
            )
        ]

        for filename in files:
            filepath = os.path.join(root, filename)
            if any(fnmatch.fnmatch(filepath, pattern) for pattern in exclude_patterns):
                continue

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
        help="The new release version (e.g., 0.28.0).",
        type=_semver_type,
    )
    return parser


def main():
    parser = create_parser()
    args = parser.parse_args()

    if not re.match(r"^\d+\.\d+\.\d+(rc\d+)?$", args.version):
        raise ValueError(
            f"Version '{args.version}' is not a valid semantic version (X.Y.Z or X.Y.ZrcN)"
        )

    # Change to the workspace root so the script can be run from anywhere.
    if "BUILD_WORKSPACE_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKSPACE_DIRECTORY"])

    print("Updating changelog ...")
    release_date = datetime.date.today().strftime("%Y-%m-%d")
    update_changelog(args.version, release_date)

    print("Replacing VERSION_NEXT placeholders ...")
    replace_version_next(args.version)

    print("Done")


if __name__ == "__main__":
    main()

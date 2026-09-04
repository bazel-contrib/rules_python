"""Subcommand to process news files and version markers for a release."""

import argparse
import dataclasses
import datetime
import logging
import pathlib
import re
import sys

from tools.private.release import changelog_news
from tools.private.release.gh import (
    GetPrError,
    GitHub,
    GitHubInterface,
    InvalidPrRefError,
)
from tools.private.release.utils import replace_version_next_in_files

logger = logging.getLogger(__name__)


def _release_version_type(value: str) -> str:
    """Argparse type validator for release versions (X.Y or X.Y.Z)."""
    if not re.match(r"^\d+\.\d+(\.\d+)?(rc\d+)?$", value):
        raise argparse.ArgumentTypeError(
            f"'{value}' is not a valid release version (X.Y or X.Y.Z)"
        )
    return value


@dataclasses.dataclass(frozen=True)
class NewsFileTarget:
    """Represents a direct news file target."""

    path: pathlib.Path


@dataclasses.dataclass(frozen=True)
class PrTarget:
    """Represents a PR target with its news files and code files."""

    pr_num: int
    news_files: tuple[pathlib.Path, ...]
    code_files: tuple[pathlib.Path, ...]


ResolvedTarget = NewsFileTarget | PrTarget


def resolve_news_file_target(target: str) -> NewsFileTarget | None:
    """Attempts to resolve a target as a direct news file path on disk."""
    path = pathlib.Path(target)
    if path.exists() and changelog_news.is_news_file(path):
        return NewsFileTarget(path=path)
    return None


def resolve_pr_target(target: str, gh: GitHubInterface) -> PrTarget | None:
    """Attempts to resolve a target as a PR reference and discover its files."""
    try:
        pr_num = gh.resolve_pr_number(target)
    except InvalidPrRefError:
        return None

    logger.info("Resolving files for PR #%d via GitHub CLI...", pr_num)
    try:
        pr_file_paths = gh.get_pr_files(pr_num)
    except GetPrError as e:
        logger.error("Failed to get PR files for #%d: %s", pr_num, e)
        print(f"::error::Failed to get files for PR #{pr_num}: {e}")
        raise

    news_files: list[pathlib.Path] = []
    code_files: list[pathlib.Path] = []

    # Check local news directory for any news/<pr_num>.*.md
    news_dir = pathlib.Path("news")
    if news_dir.is_dir():
        for p in news_dir.iterdir():
            if p.name.startswith(f"{pr_num}.") and changelog_news.is_news_file(p):
                if p not in news_files:
                    news_files.append(p)

    for f in pr_file_paths:
        p = pathlib.Path(f)
        if changelog_news.is_news_file(p):
            if p.exists() and p not in news_files:
                news_files.append(p)
        else:
            if p.exists() and p not in code_files:
                code_files.append(p)

    if not pr_file_paths and not news_files:
        msg = f"No news files or PR files found for PR #{pr_num}."
        logger.error(msg)
        print(f"::error::{msg}")
        raise GetPrError(msg)

    return PrTarget(
        pr_num=pr_num,
        news_files=tuple(news_files),
        code_files=tuple(code_files),
    )


def resolve_target(target: str, gh: GitHubInterface) -> ResolvedTarget:
    """Resolves a target string into a ResolvedTarget.

    Raises:
        ValueError: If target cannot be resolved.
    """
    if news_target := resolve_news_file_target(target):
        return news_target

    try:
        if pr_target := resolve_pr_target(target, gh):
            return pr_target
    except (InvalidPrRefError, GetPrError):
        raise

    path = pathlib.Path(target)
    if path.exists():
        msg = f"File is not a valid news file: {path} (expected <id>.<category>.md)"
    else:
        msg = (
            f"Target '{target}' is neither an existing news file nor a valid PR"
            " reference."
        )
    print(f"::error::{msg}")
    raise ValueError(msg)


def process_news_file_target(
    target: NewsFileTarget,
    version: str,
    changelog_path: pathlib.Path,
    release_date: str | None = None,
) -> None:
    """Processes a direct news file target."""
    if release_date is None:
        release_date = datetime.date.today().strftime("%Y-%m-%d")
    logger.info("Processing news file: %s", target.path)
    changelog_news.update_changelog(
        version=version,
        release_date=release_date,
        changelog_path=changelog_path,
        news_files=[target.path],
        delete_news=True,
    )
    print(f"::notice::Processed news file {target.path} into {changelog_path}.")


def process_pr_target(
    target: PrTarget,
    version: str,
    changelog_path: pathlib.Path,
    release_date: str | None = None,
) -> None:
    """Processes a PR target: merges news files and updates version markers."""
    if release_date is None:
        release_date = datetime.date.today().strftime("%Y-%m-%d")
    logger.info("Processing PR #%d...", target.pr_num)
    if target.news_files:
        changelog_news.update_changelog(
            version=version,
            release_date=release_date,
            changelog_path=changelog_path,
            news_files=list(target.news_files),
            delete_news=True,
        )
        news_list_str = ", ".join(str(f) for f in target.news_files)
        print(
            f"::notice::Processed news file(s) for PR #{target.pr_num} into"
            f" {changelog_path}: {news_list_str}"
        )

    if target.code_files:
        modified_files = replace_version_next_in_files(target.code_files, version)
        if modified_files:
            mod_str = ", ".join(str(f) for f in modified_files)
            print(
                f"::notice::Updated version-next markers for PR #{target.pr_num} in:"
                f" {mod_str}"
            )
        else:
            logger.info(
                "No version-next markers found to update for PR #%d.",
                target.pr_num,
            )


class ProcessNews:
    """Class to process news files into CHANGELOG.md for a release."""

    def __init__(self, args, gh: GitHubInterface):
        self.args = args
        self.gh = gh

    def run(self) -> int:
        """Executes the process-news subcommand."""
        args = self.args
        version = args.version
        if len(version.split(".")) == 2:
            version = f"{version}.0"

        # Validate that target version exists in CHANGELOG.md
        changelog_path = pathlib.Path("CHANGELOG.md")
        if not changelog_path.exists():
            print(
                f"::error::Changelog file not found at {changelog_path}",
                file=sys.stderr,
            )
            return 1

        header_version = version.replace(".", "-")
        version_anchor = f"{{#v{header_version}}}"

        release_date = args.release_date or datetime.date.today().strftime("%Y-%m-%d")

        # Phase 1: Resolve all targets in order
        resolved_targets: list[ResolvedTarget] = []
        for target in args.targets:
            try:
                resolved = resolve_target(target, self.gh)
                resolved_targets.append(resolved)
            except Exception as e:
                logger.error("Failed to resolve target '%s': %s", target, e)
                print(
                    f"::error::Failed to resolve target '{target}': {e}",
                    file=sys.stderr,
                )
                return 1

        # Phase 2: Process all resolved targets in the given order
        for target in resolved_targets:
            if isinstance(target, NewsFileTarget):
                process_news_file_target(
                    target, version, changelog_path, release_date=release_date
                )
            elif isinstance(target, PrTarget):
                process_pr_target(
                    target, version, changelog_path, release_date=release_date
                )
            else:
                logger.warning(
                    "Unexpected target type encountered: %s (%r)",
                    type(target),
                    target,
                )

        current_changelog = changelog_path.read_text(encoding="utf-8")
        if version_anchor not in current_changelog:
            logger.info(
                "Version anchor %s not created by targets; creating empty release section.",
                version_anchor,
            )
            changelog_news.update_changelog(
                version=version,
                release_date=release_date,
                changelog_path=changelog_path,
                news_files=[],
                delete_news=False,
            )

        return 0

    @classmethod
    def add_parser(cls, subparsers):
        """Adds parser for process-news subcommand."""
        parser = subparsers.add_parser(
            "process-news",
            help=(
                "Process news files and update version-next markers into"
                " CHANGELOG.md for a release version."
            ),
        )
        parser.add_argument(
            "version",
            type=_release_version_type,
            help="The target release version (e.g., 2.3.0 or 2.3).",
        )
        parser.add_argument(
            "targets",
            nargs="+",
            metavar="TARGET",
            help=(
                "One or more news file paths (e.g., news/3997.added.md) or PR"
                " references (e.g., 3997, #3997, or PR URL) to process."
            ),
        )
        parser.add_argument(
            "--release-date",
            type=str,
            default=None,
            help=(
                "Release date (YYYY-MM-DD) to use if creating a new version"
                " section (defaults to today)."
            ),
        )
        parser.set_defaults(command=cls.run_from_args)

    @classmethod
    def run_from_args(cls, args):
        """Instantiates and runs the command from parsed args."""
        return cls(args, gh=GitHub()).run()

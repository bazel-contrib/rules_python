"""A tool to merge news entries into CHANGELOG.md for documentation preview."""

import argparse
import pathlib

from tools.private.release import changelog_news


def main():
    parser = argparse.ArgumentParser(description="Merge news entries into CHANGELOG.md")
    parser.add_argument(
        "--changelog", type=pathlib.Path, required=True, help="Path to CHANGELOG.md"
    )
    parser.add_argument(
        "--news-dir", type=pathlib.Path, required=True, help="Path to news directory"
    )
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        required=True,
        help="Path to output merged changelog",
    )
    args = parser.parse_args()

    # Call the public merge_new_into_changelog function
    # Using deterministic date "0000-00-00" and version "0.0.0"
    changelog_news.merge_new_into_changelog(
        changelog_path=args.changelog,
        output_path=args.output,
        news_dir=args.news_dir,
        version="unreleased",
        release_date="0000-00-00",
        delete_news=False,
    )


if __name__ == "__main__":
    main()

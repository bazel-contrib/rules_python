"""Populates a declared directory artifact with relative file paths and contents.

Usage:
    populate_tree.py --output-dir <dir> [--path <rel_path> ...] [--entry <rel_path>=<text> ...]

Input format:
    `--path` creates an empty file at `<dir>/<rel_path>`; `--entry` writes UTF-8 text.
"""

from __future__ import annotations

import argparse
from collections.abc import Sequence
from pathlib import Path


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Populate a test TreeArtifact.")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--path", action="append", dest="paths", default=[])
    parser.add_argument("--entry", action="append", dest="entries", default=[])
    args = parser.parse_args(argv)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    contents: dict[str, str] = {p: "" for p in args.paths}
    for item in args.entries:
        rel_path, _, text = item.partition("=")
        contents[rel_path] = text

    for rel_path, text in sorted(contents.items()):
        dest = args.output_dir / rel_path
        dest.parent.mkdir(parents=True, exist_ok=True)
        with open(dest, "w", encoding="utf-8", newline="\n") as out_file:
            out_file.write(text)


if __name__ == "__main__":
    main()

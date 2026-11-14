"""Populates a declared directory artifact with paths, text entries, and files.

Usage:
    populate_tree.py --output-dir <dir> [--path <rel_path> ...]
        [--entry <rel_path>=<text> ...] [--copy <rel_path>=<src_path> ...]

Input format:
    `--path` creates an empty file at `<dir>/<rel_path>`; `--entry` writes UTF-8
    text; `--copy` copies `<src_path>` to `<dir>/<rel_path>`.
"""

from __future__ import annotations

import argparse
import os
import shutil
from collections.abc import Sequence
from pathlib import Path


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Populate a test TreeArtifact.")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--path", action="append", dest="paths", default=[])
    parser.add_argument("--entry", action="append", dest="entries", default=[])
    parser.add_argument("--copy", action="append", dest="copies", default=[])
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

    for item in args.copies:
        rel_path, _, src_str = item.partition("=")
        src_path = Path(src_str)
        dest = args.output_dir / rel_path
        dest.parent.mkdir(parents=True, exist_ok=True)
        if dest.exists():
            dest.unlink()
        shutil.copyfile(src_path, dest)
        if os.access(src_path, os.X_OK):
            dest.chmod(0o755)


if __name__ == "__main__":
    main()

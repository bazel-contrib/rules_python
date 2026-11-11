#!/usr/bin/env python3

"""Synchronizes Bazel downloader configuration files across subworkspaces.

Usage:
    ./dev/sync_downloader_configs.py

Copies root downloader configuration files (Bazel downloader rewrite rules and
flags) to each standalone module subworkspace and exits with status 1 if any
file was updated.
"""

import sys
from pathlib import Path

# Config filenames relative to a module root directory.
_SYNCED_FILES = (
    # keep-sorted start
    "downloader_cfg.bazelrc",
    "downloader_config.cfg",
    # keep-sorted end
)

# Standalone module subworkspace paths relative to the repository root.
_SUBWORKSPACE_DIRS = (
    # keep-sorted start
    "gazelle",
    "sphinxdocs",
    # keep-sorted end
)


def main() -> None:
    repo_root = Path(__file__).resolve().parent.parent

    updated: list[str] = []
    for filename in _SYNCED_FILES:
        canonical = repo_root / filename
        canonical_content = canonical.read_text(encoding="utf-8")
        for rel_dir in _SUBWORKSPACE_DIRS:
            sub = repo_root / rel_dir / filename
            if sub.read_text(encoding="utf-8") != canonical_content:
                sub.write_text(canonical_content, encoding="utf-8")
                updated.append(sub.relative_to(repo_root).as_posix())

    if updated:
        for rel_path in sorted(updated):
            print(f"{rel_path}: out of sync (updated from root)")
        sys.exit(1)


if __name__ == "__main__":
    main()

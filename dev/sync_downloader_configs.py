#!/usr/bin/env python3

"""Synchronizes Bazel downloader configuration files across subworkspaces.

Usage:
    ./dev/sync_downloader_configs.py

Copies root downloader configuration files (Bazel downloader rewrite rules and
flags) to each standalone module subworkspace and exits with status 1 if any
file was updated.
"""

from __future__ import annotations

import sys
from pathlib import Path

# Config filenames relative to a module root directory.
# LINT.IfChange(synced_files)
SYNCED_FILES = (
    # keep-sorted start
    "downloader_cfg.bazelrc",
    "downloader_config.cfg",
    # keep-sorted end
)
# LINT.ThenChange(//sphinxdocs/BUILD.bazel:synced_files)

# Standalone module subworkspace paths relative to the repository root.
# LINT.IfChange(subworkspace_dirs)
SUBWORKSPACE_DIRS = (
    # keep-sorted start
    "gazelle",
    "sphinxdocs",
    # keep-sorted end
)
# LINT.ThenChange(//tests/dev/BUILD.bazel:subworkspace_dirs)


def sync_downloader_configs(repo_root: Path) -> list[str]:
    """Synchronizes root downloader config files into standalone subworkspaces.

    Args:
        repo_root: Path to the repository root directory.

    Returns:
        Sorted repository-root-relative POSIX paths of files that were updated.
    """
    updated: list[str] = []
    for filename in SYNCED_FILES:
        canonical = repo_root / filename
        canonical_content = canonical.read_text(encoding="utf-8")
        for rel_dir in SUBWORKSPACE_DIRS:
            sub = repo_root / rel_dir / filename
            if sub.read_text(encoding="utf-8") != canonical_content:
                sub.write_text(canonical_content, encoding="utf-8")
                updated.append(sub.relative_to(repo_root).as_posix())
    return sorted(updated)


def main() -> None:
    repo_root = Path(__file__).resolve().parent.parent
    updated = sync_downloader_configs(repo_root)
    if updated:
        for rel_path in updated:
            print(f"{rel_path}: out of sync (updated from root)")
        sys.exit(1)


if __name__ == "__main__":
    main()

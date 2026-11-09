#!/usr/bin/env python3

"""Synchronizes downloader_config.cfg across subworkspaces.

Usage:
    ./dev/sync_downloader_configs.py

Copies the root `downloader_config.cfg` (Bazel downloader rewrite rules) to each
subworkspace config file and exits with status 1 if any file was modified.
"""

from __future__ import annotations

import sys
from pathlib import Path

# Paths relative to the repository root.
SUBWORKSPACE_CONFIGS = (
    # keep-sorted start
    "gazelle/downloader_config.cfg",
    "sphinxdocs/downloader_config.cfg",
    # keep-sorted end
)


def sync_downloader_configs(repo_root: Path) -> bool:
    """Copies the root downloader_config.cfg to subworkspaces.

    Args:
        repo_root: Path to the repository root directory.

    Returns:
        True if any subworkspace downloader_config.cfg was updated.
    """
    canonical = repo_root / "downloader_config.cfg"
    canonical_content = canonical.read_text(encoding="utf-8")

    changed = False
    for rel_path in SUBWORKSPACE_CONFIGS:
        sub = repo_root / rel_path
        old_content = sub.read_text(encoding="utf-8")
        if old_content != canonical_content:
            sub.write_text(canonical_content, encoding="utf-8")
            print(f"Updated {rel_path}")
            changed = True

    return changed


def main() -> None:
    repo_root = Path(__file__).resolve().parent.parent
    if sync_downloader_configs(repo_root):
        sys.exit(1)


if __name__ == "__main__":
    main()

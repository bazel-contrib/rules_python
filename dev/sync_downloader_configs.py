#!/usr/bin/env python3

"""Synchronizes downloader_config.cfg across subworkspaces.

Usage:
    ./dev/sync_downloader_configs.py

Copies the root `downloader_config.cfg` (Bazel downloader rewrite rules) to each
standalone module subworkspace and exits with status 1 if any file was updated.
"""

import sys
from pathlib import Path

# Standalone module subworkspace paths relative to the repository root.
_SUBWORKSPACE_DIRS = (
    # keep-sorted start
    "gazelle",
    "sphinxdocs",
    # keep-sorted end
)


def main() -> None:
    repo_root = Path(__file__).resolve().parent.parent
    canonical = repo_root / "downloader_config.cfg"
    canonical_content = canonical.read_text(encoding="utf-8")

    changed = False
    for rel_dir in _SUBWORKSPACE_DIRS:
        sub = repo_root / rel_dir / "downloader_config.cfg"
        if sub.read_text(encoding="utf-8") != canonical_content:
            sub.write_text(canonical_content, encoding="utf-8")
            print(f"Updated {sub.relative_to(repo_root)}")
            changed = True

    if changed:
        sys.exit(1)


if __name__ == "__main__":
    main()

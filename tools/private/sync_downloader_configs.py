#!/usr/bin/env python3

"""Synchronizes downloader_config.cfg across subworkspaces."""

import sys
from pathlib import Path


def main():
    repo_root = Path(__file__).resolve().parent.parent.parent
    canonical = repo_root / "downloader_config.cfg"

    subworkspaces = [
        repo_root / "gazelle" / "downloader_config.cfg",
        repo_root / "sphinxdocs" / "downloader_config.cfg",
    ]

    with open(canonical, "r", encoding="utf-8") as f:
        canonical_content = f.read()

    changed = False
    for sub in subworkspaces:
        if sub.exists():
            with open(sub, "r", encoding="utf-8") as f:
                old_content = f.read()
            if old_content != canonical_content:
                with open(sub, "w", encoding="utf-8") as f:
                    f.write(canonical_content)
                print(f"Updated {sub.relative_to(repo_root)}")
                changed = True

    if changed:
        sys.exit(1)


if __name__ == "__main__":
    main()

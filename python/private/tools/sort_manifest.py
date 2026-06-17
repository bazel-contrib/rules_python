#!/usr/bin/env python3

"""Sorts python-build-standalone manifest files by filename."""

import argparse
import sys
from pathlib import Path


def sort_manifest(manifest_path: Path) -> bool:
    """Sorts a manifest file in place by filename. Returns True if modified."""
    # Read using pathlib.Path
    lines = manifest_path.read_text(encoding="utf-8").splitlines(keepends=True)

    if not lines:
        return False

    first_entry_idx = -1
    last_entry_idx = -1
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            if first_entry_idx == -1:
                first_entry_idx = idx
            last_entry_idx = idx

    if first_entry_idx == -1:
        return False

    # Extract top-level comments (comments at the top followed by a blank newline)
    top_level_comments = []
    pre_entry_lines = lines[:first_entry_idx]

    last_blank_idx = -1
    for idx, line in enumerate(pre_entry_lines):
        if not line.strip():
            last_blank_idx = idx

    if last_blank_idx != -1:
        top_level_comments = pre_entry_lines[: last_blank_idx + 1]
        remaining_pre = pre_entry_lines[last_blank_idx + 1 :]
    else:
        remaining_pre = pre_entry_lines

    # Extract bottom-level comments
    bottom_level_comments = lines[last_entry_idx + 1 :]

    # Group middle lines into actual catalog entries with their attached comments/blank lines
    middle_lines = remaining_pre + lines[first_entry_idx : last_entry_idx + 1]

    entries = []
    current_attached = []

    for line in middle_lines:
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            parts = [p for p in stripped.split(" ") if p]
            if len(parts) == 2:
                sha256, filename = parts[0], parts[1]
                normalized_line = f"{sha256}  {filename}\n"
            else:
                filename = parts[0] if parts else ""
                normalized_line = line

            block = current_attached + [normalized_line]
            entries.append((filename, block))
            current_attached = []
        else:
            current_attached.append(line)

    if current_attached:
        bottom_level_comments = current_attached + bottom_level_comments

    # Sort entries lexicographically by filename
    entries.sort(key=lambda e: e[0])

    new_lines = top_level_comments
    for _, block in entries:
        new_lines.extend(block)
    new_lines.extend(bottom_level_comments)

    if new_lines == lines:
        return False

    manifest_path.write_text("".join(new_lines), encoding="utf-8")
    return True


def main():
    parser = argparse.ArgumentParser(description="Sort manifest files by filename.")
    parser.add_argument(
        "manifests",
        nargs="*",
        type=Path,
        help="Path to manifest files to sort.",
    )
    args = parser.parse_args()

    manifests = args.manifests
    if not manifests:
        repo_root = Path(__file__).resolve().parent.parent.parent.parent
        default_manifest = repo_root / "python" / "private" / "runtimes_manifest.txt"
        if default_manifest.exists():
            manifests = [default_manifest]
        else:
            print("No manifests provided.", file=sys.stderr)
            sys.exit(1)

    changed = False
    for m in manifests:
        if m.exists():
            if sort_manifest(m):
                print(f"Sorted {m}")
                changed = True
        else:
            print(f"Warning: Manifest not found: {m}", file=sys.stderr)

    if changed:
        sys.exit(1)


if __name__ == "__main__":
    main()

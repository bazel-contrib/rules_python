"""Inspect a wheel archive without extracting it to disk.

Writes a JSON object to stdout containing `entry_points_content`,
`extracted_files`, `has_entry_points_txt`, `metadata_content`,
`namespace_package_files`, and `shebang_scripts` for BUILD generation.

Usage:
    python3 -I -B inspect_whl.py --wheel path/to/pkg-1.0-py3-none-any.whl \\
        [--srcs-exclude-glob PATTERN ...] [--data-exclude-glob PATTERN ...]
"""

from __future__ import annotations

import argparse
import json
import sys
import zipfile
from collections.abc import Sequence
from pathlib import Path
from typing import TypedDict

# Invoked directly via `rctx.execute([python_interpreter, ...])` during
# repository fetch before any `py_binary` target can be built, so Bazel's
# `py_binary` import path setup is unavailable.
sys.path.insert(0, str(Path(__file__).resolve().parent))

from wheel_layout import (  # noqa: E402
    find_wheel_dist_info_and_entry_points,
    glob_to_regex,
    is_excluded,
    is_pkgutil_namespace_init,
    plan_wheel_entries,
)


def _is_top_level_pkg_init(dest_rel: str) -> bool:
    parts = dest_rel.split("/")
    return (
        len(parts) == 3
        and parts[0] == "site-packages"
        and parts[2] == "__init__.py"
        and parts[1].isidentifier()
    )


class WheelInspection(TypedDict):
    entry_points_content: str
    extracted_files: list[str]
    has_entry_points_txt: bool
    metadata_content: str
    namespace_package_files: list[str]
    shebang_scripts: list[str]


def inspect_wheel(
    wheel_path: Path,
    srcs_exclude_globs: list[str] | None = None,
    data_exclude_globs: list[str] | None = None,
) -> WheelInspection:
    """Inspect a .whl zip file and return metadata and extracted file paths."""
    srcs_exclude_rx = [glob_to_regex(p) for p in (srcs_exclude_globs or ())]
    data_exclude_rx = [glob_to_regex(p) for p in (data_exclude_globs or ())]

    extracted_files: set[str] = set()
    namespace_package_files: set[str] = set()
    shebang_scripts: set[str] = set()

    with zipfile.ZipFile(wheel_path) as z:
        dist_info_dir, metadata_content, entry_points_content = (
            find_wheel_dist_info_and_entry_points(z)
        )
        for info, dest_or_script, is_shebang in plan_wheel_entries(
            z,
            dist_info_dir,
            entry_points_content,
            srcs_exclude_rx,
            data_exclude_rx,
        ):
            if is_shebang:
                shebang_scripts.add(dest_or_script)
                continue
            extracted_files.add(dest_or_script)
            if not _is_top_level_pkg_init(dest_or_script):
                continue
            content = z.read(info).decode("utf-8", "replace")
            if is_pkgutil_namespace_init(content):
                namespace_package_files.add(dest_or_script)

    installer_rel = f"site-packages/{dist_info_dir}/INSTALLER"
    if not is_excluded(installer_rel, data_exclude_rx):
        extracted_files.add(installer_rel)

    return {
        "entry_points_content": entry_points_content or "",
        "extracted_files": sorted(extracted_files),
        "has_entry_points_txt": entry_points_content is not None,
        "metadata_content": metadata_content,
        "namespace_package_files": sorted(namespace_package_files),
        "shebang_scripts": sorted(shebang_scripts),
    }


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Inspect a wheel file.")
    parser.add_argument("--wheel", type=Path, required=True)
    parser.add_argument(
        "--srcs-exclude-glob",
        action="append",
        dest="srcs_exclude_globs",
        default=[],
    )
    parser.add_argument(
        "--data-exclude-glob",
        action="append",
        dest="data_exclude_globs",
        default=[],
    )
    args = parser.parse_args(argv)

    try:
        result = inspect_wheel(
            args.wheel, args.srcs_exclude_globs, args.data_exclude_globs
        )
    except (zipfile.BadZipFile, ValueError, OSError) as exc:
        print(
            f"inspect_whl: failed to inspect '{args.wheel}': {exc}",
            file=sys.stderr,
        )
        return 1

    json.dump(result, sys.stdout, sort_keys=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())

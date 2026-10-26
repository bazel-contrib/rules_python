"""Build-action tool to extract individual files from an installed wheel TreeArtifact.

Copies requested `REL_PATH=DEST_PATH` entries from `--wheel-dir` (or from
`--fallback-wheel` when `.py` sources were omitted during precompilation) into
declared output `File` paths.

Usage:
    python3 -B wheel_files_extractor.py --wheel-dir path/to/installed_dir \\
        --entry site-packages/pkg/data.json=bazel-out/.../data.json \\
        [--fallback-wheel path/to/pkg.whl] [--executable]
"""

from __future__ import annotations

import argparse
import os
import shutil
import zipfile
from collections.abc import Sequence
from pathlib import Path

from wheel_layout import (
    find_wheel_dist_info_and_entry_points,
    plan_wheel_entries,
    single_wheel_in,
)


def _load_fallback_wheel_bytes(fallback_wheel: Path) -> dict[str, bytes]:
    fallback_bytes: dict[str, bytes] = {}
    whl_file = (
        single_wheel_in(fallback_wheel) if fallback_wheel.is_dir() else fallback_wheel
    )
    with zipfile.ZipFile(whl_file) as z:
        dist_info_dir, _, entry_points_content = find_wheel_dist_info_and_entry_points(
            z
        )
        for info, dest_or_script, is_shebang in plan_wheel_entries(
            z,
            dist_info_dir,
            entry_points_content,
            [],
            [],
        ):
            dest_rel = f"bin/{dest_or_script}" if is_shebang else dest_or_script
            fallback_bytes[dest_rel] = z.read(info)
    return fallback_bytes


def extract_wheel_files(
    wheel_dir: Path,
    entries: list[tuple[str, Path]],
    *,
    executable: bool = False,
    fallback_wheel: Path | None = None,
) -> None:
    """Copy each `(rel_path, out_path)` from `wheel_dir` (or `fallback_wheel`) to `out_path`."""
    wheel_root = Path(os.path.abspath(wheel_dir))
    fallback_bytes: dict[str, bytes] | None = None
    for rel_path, out_path in entries:
        if not rel_path or rel_path.startswith("/") or "\\" in rel_path:
            raise ValueError(f"Unsafe relative path for wheel extraction: {rel_path!r}")
        src_path = wheel_dir / rel_path
        src_abs = Path(os.path.abspath(src_path))
        if not src_abs.is_relative_to(wheel_root) or src_abs == wheel_root:
            raise ValueError(
                f"Extraction path '{rel_path}' escapes wheel directory '{wheel_dir}'"
            )
        if (
            not src_path.is_file()
            and rel_path.startswith("bin/")
            and not rel_path.endswith(".bat")
        ):
            bat_candidate = wheel_dir / f"{rel_path}.bat"
            if bat_candidate.is_file():
                src_path = bat_candidate
        if src_path.is_file():
            out_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src_path, out_path)
            if executable:
                os.chmod(out_path, os.stat(out_path).st_mode | 0o111)
            continue

        if fallback_wheel is None:
            raise FileNotFoundError(
                f"File '{rel_path}' does not exist in installed wheel directory '{wheel_dir}'"
            )
        if fallback_bytes is None:
            fallback_bytes = _load_fallback_wheel_bytes(fallback_wheel)
        if rel_path not in fallback_bytes:
            raise FileNotFoundError(
                f"File '{rel_path}' does not exist in installed wheel directory '{wheel_dir}'"
            )
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_bytes(fallback_bytes[rel_path])
        if executable:
            os.chmod(out_path, os.stat(out_path).st_mode | 0o111)


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        description="Extract individual files from an installed wheel TreeArtifact.",
        fromfile_prefix_chars="@",
    )
    parser.add_argument("--wheel-dir", type=Path, required=True)
    parser.add_argument(
        "--fallback-wheel",
        type=Path,
        default=None,
    )
    parser.add_argument(
        "--entry",
        action="append",
        dest="entries",
        default=[],
        help="Mapping of '<tree_rel_path>=<output_file_path>'.",
    )
    parser.add_argument(
        "--executable",
        action="store_true",
        default=False,
    )
    args = parser.parse_args(argv)

    parsed_entries: list[tuple[str, Path]] = []
    for item in args.entries:
        rel_path, sep, out_str = item.partition("=")
        if not sep or not rel_path or not out_str:
            raise ValueError(f"Invalid --entry specification: {item!r}")
        parsed_entries.append((rel_path, Path(out_str)))

    extract_wheel_files(
        args.wheel_dir,
        parsed_entries,
        executable=args.executable,
        fallback_wheel=args.fallback_wheel,
    )


if __name__ == "__main__":
    main()

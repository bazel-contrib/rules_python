"""Shared wheel layout mapping and path sanitization for inspect_whl and action_whl_installer."""

from __future__ import annotations

import base64
import csv
import hashlib
import io
import re
import zipfile
from collections.abc import Iterator
from pathlib import Path

_BAZEL_REPO_FILES = frozenset(
    {
        "BUILD",
        "BUILD.bazel",
        "REPO.bazel",
        "WORKSPACE",
        "WORKSPACE.bazel",
        "WORKSPACE.bzlmod",
    }
)

_DATA_CATEGORIES = {
    "data": "data",
    "headers": "include",
    "platlib": "site-packages",
    "purelib": "site-packages",
    "scripts": "bin",
}

INSTALLER_URL = "https://github.com/bazel-contrib/rules_python#pipstar"


def glob_to_regex(pattern: str) -> re.Pattern[str]:
    """Convert a Bazel-style glob pattern (supporting `**`) into a compiled regex."""
    i = 0
    n = len(pattern)
    parts = ["^"]
    while i < n:
        if pattern[i : i + 3] == "**/":
            parts.append("(?:.+/)?")
            i += 3
        elif pattern[i : i + 3] == "/**":
            parts.append("(?:/.*)?")
            i += 3
        elif pattern[i : i + 2] == "**":
            parts.append(".*")
            i += 2
        elif pattern[i] == "*":
            parts.append("[^/]*")
            i += 1
        elif pattern[i] == "?":
            parts.append("[^/]")
            i += 1
        else:
            parts.append(re.escape(pattern[i]))
            i += 1
    parts.append("$")
    return re.compile("".join(parts))


def is_excluded(path: str, compiled_globs: list[re.Pattern[str]]) -> bool:
    """Return whether `path` matches any compiled exclusion glob."""
    return any(rx.match(path) for rx in compiled_globs)


def is_pkgutil_namespace_init(content: str) -> bool:
    """Whether an `__init__.py` declares a pkgutil namespace package."""
    return (
        "__path__ =" in content and "pkgutil" in content and "extend_path(" in content
    )


def _parse_entry_point_names_lower(contents: str) -> set[str]:
    """Parse lowercase console_scripts and gui_scripts names from entry_points.txt."""
    names: set[str] = set()
    current_group_lower = None
    for line in contents.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            current_group_lower = line[1:-1].strip().lower()
            continue
        if current_group_lower not in ("console_scripts", "gui_scripts"):
            continue
        name, _, _ = line.partition("=")
        name = name.strip()
        if name:
            names.add(name.lower())
    return names


def sanitize_wheel_entry_path(name: str) -> list[str] | None:
    """Validate and split a wheel zip member path into normalized path components.

    Returns None for directory entries (`name.endswith("/")`).
    Raises ValueError if the path is absolute, contains backslashes, drive
    letters, empty segments, `.`, or `..`.
    """
    if name.endswith("/"):
        return None
    if name.startswith("/") or "\\" in name:
        raise ValueError(f"Unsafe wheel entry path: {name!r}")
    parts = name.split("/")
    if ":" in parts[0]:
        raise ValueError(f"Unsafe wheel entry path: {name!r}")
    for part in parts:
        if part in ("", ".", ".."):
            raise ValueError(f"Unsafe wheel entry path: {name!r}")
    return parts


def find_wheel_dist_info_and_entry_points(
    zf: zipfile.ZipFile,
) -> tuple[str, str, str | None]:
    """Return `(dist_info_dir, metadata_content, entry_points_content)` for `zf`.

    `entry_points_content` is `None` when the `.dist-info` directory contains no
    `entry_points.txt` file. Raises `ValueError` if zero or multiple top-level
    `<pkg>.dist-info/METADATA` files exist in the archive.
    """
    metadata_infos: dict[str, zipfile.ZipInfo] = {}
    entry_points_infos: dict[str, zipfile.ZipInfo] = {}

    for info in zf.infolist():
        parts = sanitize_wheel_entry_path(info.filename)
        if parts is None or len(parts) != 2 or not parts[0].endswith(".dist-info"):
            continue
        if parts[1] == "METADATA":
            metadata_infos.setdefault(parts[0], info)
        elif parts[1] == "entry_points.txt":
            entry_points_infos.setdefault(parts[0], info)

    if not metadata_infos:
        raise ValueError("Wheel archive contains no '*.dist-info/METADATA' file")
    if len(metadata_infos) > 1:
        dirs = ", ".join(sorted(metadata_infos))
        raise ValueError(
            f"Wheel archive contains multiple .dist-info directories: {dirs}"
        )

    dist_info_dir, metadata_info = next(iter(metadata_infos.items()))
    metadata_content = zf.read(metadata_info).decode("utf-8", "replace")
    ep_info = entry_points_infos.get(dist_info_dir)
    entry_points_content = (
        zf.read(ep_info).decode("utf-8", "replace") if ep_info is not None else None
    )
    return dist_info_dir, metadata_content, entry_points_content


def expected_data_dir_for_dist_info(dist_info_dir: str) -> str:
    """Derive the PEP 427 `.data` directory name from the `.dist-info` directory name."""
    return dist_info_dir[: -len(".dist-info")] + ".data"


def _resolve_wheel_entry_dest(
    name: str,
    parts: list[str],
    expected_data_dir: str,
) -> str | None:
    if parts[-1] in _BAZEL_REPO_FILES:
        return None
    if parts[0] != expected_data_dir:
        return f"site-packages/{name}"
    if len(parts) <= 2:
        return None
    dest_prefix = _DATA_CATEGORIES.get(parts[1])
    if not dest_prefix:
        raise ValueError(f"Unknown .data category {parts[1]!r} in wheel entry {name!r}")
    rel_path = "/".join(parts[2:])
    return f"{dest_prefix}/{rel_path}" if rel_path else None


def _map_wheel_entry_destination(
    name: str,
    parts: list[str],
    expected_data_dir: str,
    seen_destinations: dict[str, str],
) -> str | None:
    """Map a wheel archive entry to its installed relative path under the TreeArtifact root.

    Raises ValueError if an unknown `.data` category is encountered or if two
    distinct wheel entries map to the same destination path (checked
    case-insensitively across platforms).
    """
    dest_rel = _resolve_wheel_entry_dest(name, parts, expected_data_dir)
    if dest_rel is None:
        return None

    dest_key = dest_rel.casefold()
    prev = seen_destinations.get(dest_key)
    if prev is not None and prev != name:
        raise ValueError(
            f"Detected collision at '{dest_rel}' between wheel entries '{prev}' and '{name}'"
        )
    seen_destinations[dest_key] = name
    return dest_rel


def _has_python_shebang(zf: zipfile.ZipFile, info: zipfile.ZipInfo) -> bool:
    with zf.open(info) as f:
        return f.read(10).startswith(b"#!python")


def plan_wheel_entries(
    zf: zipfile.ZipFile,
    dist_info_dir: str,
    entry_points_content: str | None,
    srcs_exclude_rx: list[re.Pattern[str]],
    data_exclude_rx: list[re.Pattern[str]],
) -> Iterator[tuple[zipfile.ZipInfo, str, bool]]:
    """Yield `(info, dest_rel_or_script_name, is_shebang_script)` for wheel entries."""
    expected_data_dir = expected_data_dir_for_dist_info(dist_info_dir)
    ep_names_lower = _parse_entry_point_names_lower(entry_points_content or "")
    seen_destinations: dict[str, str] = {}

    for info in zf.infolist():
        name = info.filename
        parts = sanitize_wheel_entry_path(name)
        if parts is None:
            continue

        dest_rel = _map_wheel_entry_destination(
            name,
            parts,
            expected_data_dir,
            seen_destinations,
        )
        if dest_rel is None:
            continue

        if dest_rel.startswith("site-packages/"):
            exclude_rx = (
                srcs_exclude_rx if dest_rel.endswith(".py") else data_exclude_rx
            )
            if is_excluded(dest_rel, exclude_rx):
                continue

        is_top_level_bin = dest_rel.startswith("bin/") and dest_rel.count("/") == 1
        if not is_top_level_bin:
            yield info, dest_rel, False
            continue

        script_name = dest_rel[len("bin/") :]
        if script_name.lower() in ep_names_lower:
            continue

        is_shebang_script = not script_name.endswith(
            (".exe", ".dll")
        ) and _has_python_shebang(zf, info)
        if is_shebang_script:
            yield info, script_name, True
            continue

        yield info, dest_rel, False


def create_namespace_inits(site_packages_dir: Path, init_content: str) -> None:
    """Populate pkgutil-style `__init__.py` files for implicit namespace packages."""
    all_rel_files = sorted(
        p.relative_to(site_packages_dir).as_posix()
        for p in site_packages_dir.rglob("*")
        if p.is_file()
    )

    dirs: dict[str, None] = {}
    ignored: dict[str, None] = {}

    def add_all(dirname: str, target: dict[str, None]) -> None:
        dir_path = "."
        for dir_name in dirname.split("/"):
            dir_path = f"{dir_path}/{dir_name}"
            target[dir_path[2:]] = None

    for file_rel in all_rel_files:
        if "__pycache__" in file_rel.split("/"):
            continue
        dirname, _, filename = file_rel.rpartition("/")
        if filename == "__init__.py":
            ignored[dirname] = None
            dirname, _, _ = dirname.rpartition("/")
        elif not filename.endswith((".py", ".pyd", ".so")):
            continue

        if dirname in dirs or not dirname:
            continue
        add_all(dirname, dirs)

    for d in sorted(d for d in dirs if d not in ignored):
        init_path = site_packages_dir / d / "__init__.py"
        if not init_path.exists():
            with open(init_path, "w", encoding="utf-8", newline="\n") as f:
                f.write(init_content)


def _record_row(entry_path: str, full_path: Path) -> list[str]:
    if entry_path.endswith((".pyc", ".pyo")):
        return [entry_path, "", ""]
    data = full_path.read_bytes()
    digest = (
        base64.urlsafe_b64encode(hashlib.sha256(data).digest())
        .rstrip(b"=")
        .decode("ascii")
    )
    return [entry_path, f"sha256={digest}", str(len(data))]


def update_record_for_touched_files(
    site_packages_dir: Path,
    dist_info_dir: str,
    touched_site_rel_paths: set[str],
) -> None:
    """Update RECORD in `site-packages/<dist_info_dir>/RECORD` for touched files."""
    record_path = site_packages_dir / dist_info_dir / "RECORD"
    if not record_path.is_file():
        return

    existing_text = record_path.read_text(encoding="utf-8")
    out_buf = io.StringIO()
    writer = csv.writer(out_buf, lineterminator="\n")
    seen_touched: set[str] = set()

    for row in csv.reader(io.StringIO(existing_text)):
        if not row:
            continue
        entry_path = row[0]
        if entry_path not in touched_site_rel_paths:
            writer.writerow(row)
            continue
        seen_touched.add(entry_path)
        full_path = site_packages_dir / entry_path
        if full_path.is_file():
            writer.writerow(_record_row(entry_path, full_path))

    for entry_path in sorted(touched_site_rel_paths - seen_touched):
        full_path = site_packages_dir / entry_path
        if full_path.is_file():
            writer.writerow(_record_row(entry_path, full_path))

    with open(record_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(out_buf.getvalue())

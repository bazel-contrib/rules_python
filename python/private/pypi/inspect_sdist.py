"""Inspect a Python source distribution (.tar.gz / .zip) without building it.

Writes a JSON object to stdout containing `build_requires`,
`entry_points_content`, `namespace_package_files`, `provides_extra`,
`requires_dist`, and `site_paths` for BUILD generation.

Usage:
    python3 -I -B inspect_sdist.py --sdist path/to/pkg-1.0.tar.gz
"""

from __future__ import annotations

import argparse
import email.parser
import importlib
import json
import posixpath
import sys
import tarfile
import zipfile
from pathlib import Path
from typing import TypedDict

_THIS_DIR = Path(__file__).parent
# Invoked directly via `rctx.execute([python, "inspect_sdist.py", ...])` without
# Bazel runfiles/package PYTHONPATH, so add the script's directory to import
# sibling `wheel_layout`.
if str(_THIS_DIR) not in sys.path:
    sys.path.insert(0, str(_THIS_DIR))

from wheel_layout import is_pkgutil_namespace_init  # noqa: E402

_PY_EXTENSIONS = frozenset({".py", ".pyi"})
_EXCLUDED_TOP_DIRS = frozenset(
    {
        "benchmark",
        "benchmarks",
        "build",
        "dist",
        "doc",
        "docs",
        "example",
        "examples",
        "test",
        "testing",
        "tests",
    }
)
_EXCLUDED_ROOT_MODULES = frozenset(
    {
        "conf.py",
        "conftest.py",
        "noxfile.py",
        "setup.py",
        "tasks.py",
    }
)


def _read_archive_files(sdist_path: Path) -> tuple[list[str], dict[str, bytes]]:
    """Read file list and key metadata/init files from an sdist archive."""
    raw_entries: list[str] = []
    raw_contents: dict[str, bytes] = {}

    def _should_read(name: str) -> bool:
        base = posixpath.basename(name)
        if base in ("PKG-INFO", "pyproject.toml", "__init__.py"):
            return True
        return ".egg-info/" in name and base in (
            "PKG-INFO",
            "requires.txt",
            "top_level.txt",
            "entry_points.txt",
        )

    if zipfile.is_zipfile(sdist_path):
        with zipfile.ZipFile(sdist_path) as zf:
            for info in zf.infolist():
                if info.is_dir() or info.filename.endswith("/"):
                    continue
                norm = posixpath.normpath(info.filename)
                if norm.startswith(("/", "..")):
                    continue
                raw_entries.append(norm)
                if _should_read(norm):
                    raw_contents[norm] = zf.read(info)
    else:
        with tarfile.open(sdist_path, "r:*") as tf:
            for member in tf.getmembers():
                if not member.isfile():
                    continue
                norm = posixpath.normpath(member.name)
                if norm.startswith(("/", "..")):
                    continue
                raw_entries.append(norm)
                if _should_read(norm):
                    fobj = tf.extractfile(member)
                    if fobj is not None:
                        raw_contents[norm] = fobj.read()

    top_dirs = {p.split("/", 1)[0] for p in raw_entries if "/" in p}
    root_files = [p for p in raw_entries if "/" not in p]
    if len(top_dirs) == 1 and not root_files:
        prefix = next(iter(top_dirs)) + "/"
        entries = [p[len(prefix) :] for p in raw_entries if p.startswith(prefix)]
        contents = {
            k[len(prefix) :]: v for k, v in raw_contents.items() if k.startswith(prefix)
        }
        return sorted(entries), contents

    return sorted(raw_entries), raw_contents


def _parse_pkg_info(text: str) -> tuple[bool, list[str], list[str]]:
    msg = email.parser.Parser().parsestr(text, headersonly=True)
    ver_parts = (msg.get("Metadata-Version") or "").strip().split(".")
    try:
        mv = (int(ver_parts[0]), int(ver_parts[1]) if len(ver_parts) > 1 else 0)
    except ValueError:
        mv = (0, 0)
    dynamic = {d.strip().lower() for d in (msg.get_all("Dynamic") or ())}
    static = mv >= (2, 2) and not ({"requires-dist", "provides-extra"} & dynamic)
    requires_dist = [
        r.strip() for r in (msg.get_all("Requires-Dist") or ()) if r.strip()
    ]
    provides_extra = [
        e.strip() for e in (msg.get_all("Provides-Extra") or ()) if e.strip()
    ]
    return static, requires_dist, provides_extra


def _combine_req_and_marker(req: str, extra: str, marker: str) -> str:
    req = req.strip()
    existing_marker = ""
    if ";" in req:
        req_part, _, existing_marker = req.partition(";")
        req = req_part.strip()
        existing_marker = existing_marker.strip()

    conditions: list[str] = []
    if existing_marker:
        conditions.append(
            f"({existing_marker})" if (extra or marker) else existing_marker
        )
    if marker:
        conditions.append(f"({marker})" if (existing_marker or extra) else marker)
    if extra:
        conditions.append(f'extra == "{extra}"')

    if conditions:
        return f"{req} ; {' and '.join(conditions)}"
    return req


def _parse_egg_info_requires_txt(text: str) -> tuple[list[str], list[str]]:
    requires_dist: list[str] = []
    provides_extra: list[str] = []
    current_extra = ""
    current_marker = ""

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip()
            if ":" in section:
                extra_part, _, marker_part = section.partition(":")
                current_extra = extra_part.strip()
                current_marker = marker_part.strip()
            else:
                current_extra = section
                current_marker = ""
            if current_extra and current_extra not in provides_extra:
                provides_extra.append(current_extra)
            continue

        requires_dist.append(
            _combine_req_and_marker(line, current_extra, current_marker)
        )

    return requires_dist, provides_extra


def _parse_toml(text: str) -> dict[str, object]:
    if sys.version_info >= (3, 11):
        import tomllib

        loads = tomllib.loads
    else:
        try:
            tomli = importlib.import_module("tomli")
        except ModuleNotFoundError as exc:
            raise RuntimeError(
                "Neither tomllib nor tomli is available to parse pyproject.toml"
            ) from exc
        loads = tomli.loads
    try:
        parsed = loads(text)
    except Exception as exc:
        raise ValueError(f"Failed to parse pyproject.toml: {exc}") from exc
    return parsed if isinstance(parsed, dict) else {}


def _format_entry_points_txt(
    console_scripts: dict[str, str],
    gui_scripts: dict[str, str],
) -> str:
    sections: list[str] = []
    if console_scripts:
        lines = ["[console_scripts]"] + [
            f"{k} = {v}" for k, v in sorted(console_scripts.items())
        ]
        sections.append("\n".join(lines))
    if gui_scripts:
        lines = ["[gui_scripts]"] + [
            f"{k} = {v}" for k, v in sorted(gui_scripts.items())
        ]
        sections.append("\n".join(lines))
    return "\n\n".join(sections) + ("\n" if sections else "")


def _discover_site_paths_and_namespaces(
    entries: list[str],
    contents: dict[str, bytes],
    pyproject: dict[str, object],
) -> tuple[list[str], list[str]]:
    """Determine installed top-level / leaf non-namespace site_paths and pkgutil namespace init files."""
    entry_set = set(entries)

    dir_files: dict[str, list[str]] = {}
    dir_subdirs: dict[str, set[str]] = {}
    dir_has_py: set[str] = set()

    for path in entries:
        parts = path.split("/")
        if any(p.endswith(".egg-info") for p in parts[:-1]):
            continue
        parent = posixpath.dirname(path)
        base = posixpath.basename(path)
        dir_files.setdefault(parent, []).append(base)

        _, ext = posixpath.splitext(base)
        if ext.lower() in _PY_EXTENSIONS:
            dir_has_py.add(parent)
            cur = parent
            while cur:
                dir_has_py.add(cur)
                cur = posixpath.dirname(cur)

        cur = parent
        while cur:
            up = posixpath.dirname(cur)
            dir_subdirs.setdefault(up, set()).add(posixpath.basename(cur))
            cur = up

    source_root = ""
    raw_tool = pyproject.get("tool")
    tool = raw_tool if isinstance(raw_tool, dict) else {}
    raw_maturin = tool.get("maturin")
    maturin_cfg = raw_maturin if isinstance(raw_maturin, dict) else {}
    maturin_py_src = maturin_cfg.get("python-source", "")
    if (
        isinstance(maturin_py_src, str)
        and maturin_py_src.strip("/")
        and maturin_py_src.strip("/") in dir_has_py
    ):
        source_root = maturin_py_src.strip("/")
    elif (
        "src" in dir_subdirs.get("", set())
        and "src/__init__.py" not in entry_set
        and "src" in dir_has_py
    ):
        source_root = "src"

    def _archive_dir(site_rel: str) -> str:
        if source_root and f"{source_root}/{site_rel}" in dir_has_py:
            return f"{source_root}/{site_rel}"
        if site_rel in dir_has_py:
            return site_rel
        suffix = f"/{site_rel}"
        for d in sorted(dir_has_py):
            top_seg = d.partition("/")[0].lower()
            if d.endswith(suffix) and top_seg not in _EXCLUDED_TOP_DIRS:
                return d
        return f"{source_root}/{site_rel}" if source_root else site_rel

    def _module_exists_in_archive(mod_name: str) -> bool:
        if source_root and f"{source_root}/{mod_name}.py" in entry_set:
            return True
        if f"{mod_name}.py" in entry_set:
            return True
        suffix = f"/{mod_name}.py"
        return any(
            p.endswith(suffix)
            and p.partition("/")[0].lower() not in _EXCLUDED_TOP_DIRS
            and f"{p.rpartition('/')[0]}/__init__.py" not in entry_set
            for p in entries
        )

    namespace_package_files: set[str] = set()

    def _resolve_package_dir(site_rel: str, arch_rel: str) -> list[str]:
        init_arch = f"{arch_rel}/__init__.py" if arch_rel else "__init__.py"
        has_init = init_arch in entry_set
        is_ns_init = False
        if has_init:
            init_text = contents.get(init_arch, b"").decode("utf-8", "replace")
            if is_pkgutil_namespace_init(init_text):
                is_ns_init = True
                namespace_package_files.add(f"{site_rel}/__init__.py")

        is_namespace = (not has_init) or is_ns_init
        direct_non_init_files = [
            f
            for f in dir_files.get(arch_rel, [])
            if f != "__init__.py" and not f.startswith(".")
        ]
        child_dirs = sorted(
            d
            for d in dir_subdirs.get(arch_rel, set())
            if d.isidentifier() and f"{arch_rel}/{d}" in dir_has_py
        )

        if is_namespace and child_dirs and not direct_non_init_files:
            resolved: list[str] = []
            for child in child_dirs:
                resolved.extend(
                    _resolve_package_dir(f"{site_rel}/{child}", f"{arch_rel}/{child}")
                )
            return resolved
        return [site_rel]

    candidate_top_pkgs: list[str] = []
    candidate_modules: list[str] = []
    has_ext_sources = any(
        posixpath.splitext(p)[1].lower() in {".c", ".cc", ".cpp", ".cxx", ".pyx", ".rs"}
        for p in entries
    )

    for path, raw in sorted(contents.items()):
        if not path.endswith(".egg-info/top_level.txt"):
            continue
        for line in raw.decode("utf-8", "replace").splitlines():
            top = line.strip().strip("/")
            if not top or top.lower() in _EXCLUDED_TOP_DIRS:
                continue
            arch_dir = _archive_dir(top)
            if arch_dir in dir_has_py or f"{arch_dir}/__init__.py" in entry_set:
                if top not in candidate_top_pkgs:
                    candidate_top_pkgs.append(top)
                continue
            if _module_exists_in_archive(top):
                mod_file = f"{top}.py"
                if mod_file not in candidate_modules:
                    candidate_modules.append(mod_file)
                continue
            matches_entry = has_ext_sources or any(
                (f"/{top}/" in f"/{p}" or p.endswith(f"/{top}.py"))
                and p.partition("/")[0].lower() not in _EXCLUDED_TOP_DIRS
                for p in entries
            )
            if matches_entry and top not in candidate_top_pkgs:
                candidate_top_pkgs.append(top)
        break

    if not candidate_top_pkgs and not candidate_modules:
        roots_to_scan = [source_root, ""] if source_root else [""]
        for scan_root in roots_to_scan:
            for d in sorted(dir_subdirs.get(scan_root, set())):
                if (
                    not d.isidentifier()
                    or d.lower() in _EXCLUDED_TOP_DIRS
                    or d.endswith(".egg-info")
                ):
                    continue
                arch_dir = f"{scan_root}/{d}" if scan_root else d
                if arch_dir in dir_has_py and d not in candidate_top_pkgs:
                    candidate_top_pkgs.append(d)
            for f in sorted(dir_files.get(scan_root, [])):
                if (
                    f.endswith(".py")
                    and f not in _EXCLUDED_ROOT_MODULES
                    and not f.startswith("test_")
                    and not f.endswith("_test.py")
                    and f not in candidate_modules
                ):
                    candidate_modules.append(f)
            if candidate_top_pkgs or candidate_modules:
                break

    site_paths: list[str] = []
    for top_pkg in candidate_top_pkgs:
        arch_dir = _archive_dir(top_pkg)
        if arch_dir in dir_has_py:
            for sp in _resolve_package_dir(top_pkg, arch_dir):
                if sp not in site_paths:
                    site_paths.append(sp)
        elif top_pkg not in site_paths:
            site_paths.append(top_pkg)

    for mod_file in candidate_modules:
        if mod_file not in site_paths:
            site_paths.append(mod_file)

    return sorted(site_paths), sorted(namespace_package_files)


class SdistInspection(TypedDict):
    build_requires: list[str]
    entry_points_content: str
    namespace_package_files: list[str]
    provides_extra: list[str]
    requires_dist: list[str]
    site_paths: list[str]


def inspect_sdist(sdist_path: Path) -> SdistInspection:
    """Inspect an sdist archive and return dependencies, entry points, and site_paths."""
    entries, contents = _read_archive_files(sdist_path)

    pkg_info_text = ""
    if "PKG-INFO" in contents:
        pkg_info_text = contents["PKG-INFO"].decode("utf-8", "replace")
    else:
        for path, raw in sorted(contents.items()):
            if path.endswith(".egg-info/PKG-INFO"):
                pkg_info_text = raw.decode("utf-8", "replace")
                break

    pkg_info_static = False
    requires_dist: list[str] = []
    provides_extra: list[str] = []
    if pkg_info_text:
        pkg_info_static, pkg_reqs, pkg_extras = _parse_pkg_info(pkg_info_text)
        provides_extra.extend(pkg_extras)
        if pkg_reqs or pkg_info_static:
            requires_dist.extend(pkg_reqs)

    pyproject: dict[str, object] = {}
    if "pyproject.toml" in contents:
        pyproject = _parse_toml(contents["pyproject.toml"].decode("utf-8", "replace"))
    raw_project = pyproject.get("project")
    project_table = raw_project if isinstance(raw_project, dict) else {}

    if not requires_dist and not pkg_info_static:
        for path, raw in sorted(contents.items()):
            if path.endswith(".egg-info/requires.txt"):
                egg_reqs, egg_extras = _parse_egg_info_requires_txt(
                    raw.decode("utf-8", "replace")
                )
                requires_dist.extend(egg_reqs)
                for ex in egg_extras:
                    if ex not in provides_extra:
                        provides_extra.append(ex)
                break

    raw_dynamic = project_table.get("dynamic")
    project_dynamic = (
        {d for d in raw_dynamic if isinstance(d, str)}
        if isinstance(raw_dynamic, list)
        else set()
    )
    if not requires_dist and not pkg_info_static and project_table:
        if "dependencies" in project_table and "dependencies" not in project_dynamic:
            raw_deps = project_table.get("dependencies")
            if isinstance(raw_deps, list):
                for dep in raw_deps:
                    if isinstance(dep, str) and dep.strip():
                        requires_dist.append(dep.strip())
        opt_deps = project_table.get("optional-dependencies")
        if (
            isinstance(opt_deps, dict)
            and "optional-dependencies" not in project_dynamic
        ):
            for extra, deps in opt_deps.items():
                if not isinstance(extra, str):
                    continue
                if extra not in provides_extra:
                    provides_extra.append(extra)
                if not isinstance(deps, list):
                    continue
                for dep in deps:
                    if isinstance(dep, str) and dep.strip():
                        requires_dist.append(_combine_req_and_marker(dep, extra, ""))

    entry_points_content = ""
    for path, raw in sorted(contents.items()):
        if path.endswith(".egg-info/entry_points.txt"):
            entry_points_content = raw.decode("utf-8", "replace")
            break
    if not entry_points_content and project_table:
        raw_scripts = project_table.get("scripts")
        raw_gui_scripts = project_table.get("gui-scripts")
        if isinstance(raw_scripts, dict) or isinstance(raw_gui_scripts, dict):
            scripts = (
                {
                    k: v
                    for k, v in raw_scripts.items()
                    if isinstance(k, str) and isinstance(v, str)
                }
                if isinstance(raw_scripts, dict)
                else {}
            )
            gui_scripts = (
                {
                    k: v
                    for k, v in raw_gui_scripts.items()
                    if isinstance(k, str) and isinstance(v, str)
                }
                if isinstance(raw_gui_scripts, dict)
                else {}
            )
            entry_points_content = _format_entry_points_txt(scripts, gui_scripts)

    build_system = (
        pyproject.get("build-system", {}) if isinstance(pyproject, dict) else {}
    )
    build_requires: list[str] = ["setuptools", "wheel"]
    if isinstance(build_system, dict) and build_system:
        raw_requires = build_system.get("requires")
        if isinstance(raw_requires, list):
            build_requires = [
                r.strip() for r in raw_requires if isinstance(r, str) and r.strip()
            ]

    site_paths, namespace_package_files = _discover_site_paths_and_namespaces(
        entries=entries,
        contents=contents,
        pyproject=pyproject,
    )

    return {
        "build_requires": build_requires,
        "entry_points_content": entry_points_content,
        "namespace_package_files": namespace_package_files,
        "provides_extra": provides_extra,
        "requires_dist": requires_dist,
        "site_paths": site_paths,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Inspect an sdist archive.")
    parser.add_argument("--sdist", type=Path, required=True)
    args = parser.parse_args()

    json.dump(inspect_sdist(args.sdist), sys.stdout, sort_keys=True)


if __name__ == "__main__":
    main()

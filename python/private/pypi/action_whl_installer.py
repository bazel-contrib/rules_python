"""Build-action tool to extract and install a wheel into a TreeArtifact directory.

Extracts wheel entries into `<directory>/site-packages`, `<directory>/bin`,
`<directory>/data`, and `<directory>/include`, rewrites `#!python` script
shebangs and `.data` `RECORD` entries, optionally populates pkgutil namespace
`__init__.py` files, and optionally precompiles `.py` files.

Usage:
    python3 -B action_whl_installer.py --wheel path/to/pkg.whl \\
        --directory path/to/out_dir [--target-os unix|windows] \\
        [--create-namespace-inits] [--precompile --pyc-tag cpython-311]
"""

from __future__ import annotations

import argparse
import os
import py_compile
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from collections.abc import Sequence
from pathlib import Path

import wheel_layout
from venv_shebang_rewriter import rewrite_shebang_bytes
from wheel_layout import (
    INSTALLER_URL,
    create_namespace_inits,
    expected_data_dir_for_dist_info,
    find_wheel_dist_info_and_entry_points,
    glob_to_regex,
    is_excluded,
    plan_wheel_entries,
    update_record_for_touched_files,
)
from wheel_record_rewriter import rewrite_record_lines

_NAMESPACE_PKG_TMPL_PATH = (
    Path(wheel_layout.__file__ or "").parent / "namespace_pkg_tmpl.py"
)

_CompileItem = tuple[Path, str, str, Path]


def _check_in_process_python_version(python_version: str) -> None:
    if not python_version:
        return
    major_str, _, minor_str = python_version.partition(".")
    expected_ver = (int(major_str), int(minor_str))
    actual_ver = (sys.version_info.major, sys.version_info.minor)
    if actual_ver != expected_ver:
        raise ValueError(
            f"Python version mismatch for precompile: target python_version is "
            f"{expected_ver[0]}.{expected_ver[1]}, but py_exec_tools_toolchain's "
            f"exec_interpreter is {actual_ver[0]}.{actual_ver[1]}. Register an "
            f"exec_tools toolchain matching the target Python version or disable precompile."
        )


def _write_syntax_error_stub_pyc(
    pyc_path: Path,
    src_name: str,
    exc: BaseException | str,
    *,
    optimize_level: int,
    inv_mode: py_compile.PycInvalidationMode,
) -> None:
    syn: SyntaxError | None = None
    if isinstance(exc, py_compile.PyCompileError) and isinstance(
        exc.exc_value, SyntaxError
    ):
        syn = exc.exc_value
    elif isinstance(exc, SyntaxError):
        syn = exc

    if syn is not None:
        stub_src = (
            f"raise SyntaxError({syn.msg!r}, "
            f"({src_name!r}, {syn.lineno!r}, {syn.offset!r}, {syn.text!r}))\n"
        )
    else:
        stub_src = (
            f"raise SyntaxError({str(exc)!r}, ({src_name!r}, None, None, None))\n"
        )

    pyc_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", suffix=".py", delete=False
    ) as stub_f:
        stub_path = Path(stub_f.name)
        stub_f.write(stub_src)
    try:
        py_compile.compile(
            str(stub_path),
            cfile=str(pyc_path),
            dfile=src_name,
            doraise=True,
            optimize=optimize_level,
            invalidation_mode=inv_mode,
        )
    finally:
        stub_path.unlink(missing_ok=True)


def _run_precompiler_batch(
    precompiler_tool: Path,
    items: list[_CompileItem],
    *,
    invalidation_mode: str,
    optimize_level: int,
    python_version: str,
) -> bool:
    lines = [
        "--invalidation_mode",
        invalidation_mode,
        "--optimize",
        str(optimize_level),
        "--python_version",
        python_version,
    ]
    for py_path, _, src_name, pyc_path in items:
        lines.extend(
            [
                "--src",
                str(py_path),
                "--src_name",
                src_name,
                "--pyc",
                str(pyc_path),
            ]
        )
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", suffix=".params", delete=False
    ) as pf:
        param_path = Path(pf.name)
        pf.write("\n".join(lines) + "\n")
    try:
        proc = subprocess.run([str(precompiler_tool), f"@{param_path}"], check=False)
        return proc.returncode == 0
    finally:
        param_path.unlink(missing_ok=True)


def _compile_batch_or_bisect(
    precompiler_tool: Path,
    items: list[_CompileItem],
    site_packages_dir: Path,
    touched: set[str],
    *,
    invalidation_mode: str,
    inv_mode: py_compile.PycInvalidationMode,
    optimize_level: int,
    source_retention: str,
    python_version: str,
) -> None:
    if _run_precompiler_batch(
        precompiler_tool,
        items,
        invalidation_mode=invalidation_mode,
        optimize_level=optimize_level,
        python_version=python_version,
    ):
        for py_path, rel_to_site, _, pyc_path in items:
            touched.add(pyc_path.relative_to(site_packages_dir).as_posix())
            if source_retention == "omit_source":
                py_path.unlink()
                touched.add(rel_to_site)
        return

    if len(items) == 1:
        _, rel_to_site, src_name, pyc_path = items[0]
        print(
            f"WARNING: skipping precompilation of {rel_to_site}: custom precompiler exited non-zero",
            file=sys.stderr,
        )
        _write_syntax_error_stub_pyc(
            pyc_path,
            src_name,
            f"Failed to precompile {src_name}",
            optimize_level=optimize_level,
            inv_mode=inv_mode,
        )
        touched.add(pyc_path.relative_to(site_packages_dir).as_posix())
        return

    mid = len(items) // 2
    for half in (items[:mid], items[mid:]):
        _compile_batch_or_bisect(
            precompiler_tool,
            half,
            site_packages_dir,
            touched,
            invalidation_mode=invalidation_mode,
            inv_mode=inv_mode,
            optimize_level=optimize_level,
            source_retention=source_retention,
            python_version=python_version,
        )


def _compile_in_process(
    items: list[_CompileItem],
    site_packages_dir: Path,
    *,
    inv_mode: py_compile.PycInvalidationMode,
    optimize_level: int,
    source_retention: str,
) -> set[str]:
    touched: set[str] = set()
    for py_path, rel_to_site, src_name, pyc_path in items:
        try:
            py_compile.compile(
                str(py_path),
                cfile=str(pyc_path),
                dfile=src_name,
                doraise=True,
                optimize=optimize_level,
                invalidation_mode=inv_mode,
            )
        except (py_compile.PyCompileError, SyntaxError, ValueError) as exc:
            print(
                f"WARNING: skipping precompilation of {rel_to_site}: {exc}",
                file=sys.stderr,
            )
            _write_syntax_error_stub_pyc(
                pyc_path,
                src_name,
                exc,
                optimize_level=optimize_level,
                inv_mode=inv_mode,
            )
            touched.add(pyc_path.relative_to(site_packages_dir).as_posix())
            continue

        touched.add(pyc_path.relative_to(site_packages_dir).as_posix())
        if source_retention == "omit_source":
            py_path.unlink()
            touched.add(rel_to_site)
    return touched


def precompile_site_packages(
    dest_dir: Path,
    site_packages_dir: Path,
    *,
    pyc_tag: str,
    invalidation_mode: str = "checked_hash",
    optimize_level: int = 0,
    source_retention: str = "keep_source",
    python_version: str = "",
    src_name_prefix: str = "",
    precompiler_tool: Path | None = None,
) -> set[str]:
    """Compile `.py` files under `site_packages_dir` and return touched site-packages relative paths."""
    if not pyc_tag:
        raise ValueError("precompile requires a non-empty --pyc-tag")
    if precompiler_tool is None:
        _check_in_process_python_version(python_version)

    py_files = sorted(
        p
        for p in site_packages_dir.rglob("*.py")
        if p.is_file() and "__pycache__" not in p.relative_to(site_packages_dir).parts
    )
    if not py_files:
        return set()

    compile_items: list[_CompileItem] = []
    for py_path in py_files:
        rel_to_dest = py_path.relative_to(dest_dir).as_posix()
        rel_to_site = py_path.relative_to(site_packages_dir).as_posix()
        src_name = (
            f"{src_name_prefix.rstrip('/')}/{rel_to_dest}"
            if src_name_prefix
            else rel_to_dest
        )
        if source_retention == "omit_source":
            pyc_path = py_path.with_suffix(".pyc")
        else:
            # Note: optimize_level > 0 retains `{stem}.{pyc_tag}.pyc` naming (rather
            # than `.opt-N.pyc`) to match `py_library`'s precompiler behavior.
            pycache_dir = py_path.parent / "__pycache__"
            pycache_dir.mkdir(parents=True, exist_ok=True)
            pyc_path = pycache_dir / f"{py_path.stem}.{pyc_tag}.pyc"
        compile_items.append((py_path, rel_to_site, src_name, pyc_path))

    inv_mode = py_compile.PycInvalidationMode[invalidation_mode.upper()]
    if precompiler_tool is None:
        return _compile_in_process(
            compile_items,
            site_packages_dir,
            inv_mode=inv_mode,
            optimize_level=optimize_level,
            source_retention=source_retention,
        )

    touched: set[str] = set()
    _compile_batch_or_bisect(
        precompiler_tool,
        compile_items,
        site_packages_dir,
        touched,
        invalidation_mode=invalidation_mode,
        inv_mode=inv_mode,
        optimize_level=optimize_level,
        source_retention=source_retention,
        python_version=python_version,
    )
    return touched


def _write_rewritten_script(
    dest_dir: Path,
    script_name: str,
    raw_bytes: bytes,
    target_os: str,
) -> None:
    rewritten = rewrite_shebang_bytes(raw_bytes, target_os)
    out_script_name = f"{script_name}.bat" if target_os == "windows" else script_name
    out_path = dest_dir / "bin" / out_script_name
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(rewritten)
    os.chmod(out_path, os.stat(out_path).st_mode | 0o111)


def _finalize_dist_info(
    site_packages_dir: Path,
    dist_info_dir: str,
    *,
    data_exclude_rx: list[re.Pattern[str]],
    used_data_dir: bool,
    expected_data_dir: str,
    target_os: str,
    rewritten_scripts: set[str],
) -> None:
    dist_info_path = site_packages_dir / dist_info_dir
    dist_info_path.mkdir(parents=True, exist_ok=True)
    if not is_excluded(f"site-packages/{dist_info_dir}/INSTALLER", data_exclude_rx):
        with open(
            dist_info_path / "INSTALLER", "w", encoding="utf-8", newline="\n"
        ) as f:
            f.write(INSTALLER_URL)

    record_path = dist_info_path / "RECORD"
    if not (used_data_dir and record_path.is_file()):
        return

    with open(record_path, encoding="utf-8") as f:
        lines = rewrite_record_lines(
            f,
            target_os,
            expected_data_dir,
            rewritten_scripts,
        )
    with open(record_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("".join(lines))


def install_wheel(
    wheel_path: Path,
    dest_dir: Path,
    *,
    target_os: str = "unix",
    srcs_exclude_globs: list[str] | None = None,
    data_exclude_globs: list[str] | None = None,
    create_namespace_inits_flag: bool = False,
    precompile: bool = False,
    pyc_tag: str = "",
    precompile_invalidation_mode: str = "checked_hash",
    precompile_optimize_level: int = 0,
    precompile_source_retention: str = "keep_source",
    python_version: str = "",
    src_name_prefix: str = "",
    precompiler_tool: Path | None = None,
) -> None:
    """Extract and install `wheel_path` into `dest_dir`."""
    site_packages_dir = dest_dir / "site-packages"
    site_packages_dir.mkdir(parents=True, exist_ok=True)

    srcs_exclude_rx = [glob_to_regex(g) for g in (srcs_exclude_globs or ())]
    data_exclude_rx = [glob_to_regex(g) for g in (data_exclude_globs or ())]

    rewritten_scripts: set[str] = set()
    used_data_dir = False

    with zipfile.ZipFile(wheel_path) as z:
        dist_info_dir, _, entry_points_content = find_wheel_dist_info_and_entry_points(
            z
        )
        expected_data_dir = expected_data_dir_for_dist_info(dist_info_dir)
        data_dir_prefix = f"{expected_data_dir}/"

        for info, dest_or_script, is_shebang in plan_wheel_entries(
            z,
            dist_info_dir,
            entry_points_content,
            srcs_exclude_rx,
            data_exclude_rx,
        ):
            if info.filename.startswith(data_dir_prefix):
                used_data_dir = True
            if is_shebang:
                _write_rewritten_script(
                    dest_dir, dest_or_script, z.read(info), target_os
                )
                rewritten_scripts.add(dest_or_script)
                continue

            out_path = dest_dir / dest_or_script
            out_path.parent.mkdir(parents=True, exist_ok=True)
            with z.open(info) as src_f, open(out_path, "wb") as dst_f:
                shutil.copyfileobj(src_f, dst_f)

            unix_mode = (info.external_attr >> 16) & 0o777
            if (unix_mode & 0o111) or dest_or_script.startswith("bin/"):
                os.chmod(out_path, os.stat(out_path).st_mode | 0o111)

    _finalize_dist_info(
        site_packages_dir,
        dist_info_dir,
        data_exclude_rx=data_exclude_rx,
        used_data_dir=used_data_dir,
        expected_data_dir=expected_data_dir,
        target_os=target_os,
        rewritten_scripts=rewritten_scripts,
    )

    if create_namespace_inits_flag:
        create_namespace_inits(
            site_packages_dir, _NAMESPACE_PKG_TMPL_PATH.read_text(encoding="utf-8")
        )

    if not precompile:
        return

    pyc_touched = precompile_site_packages(
        dest_dir,
        site_packages_dir,
        pyc_tag=pyc_tag,
        invalidation_mode=precompile_invalidation_mode,
        optimize_level=precompile_optimize_level,
        source_retention=precompile_source_retention,
        python_version=python_version,
        src_name_prefix=src_name_prefix,
        precompiler_tool=precompiler_tool,
    )
    if pyc_touched:
        update_record_for_touched_files(
            site_packages_dir,
            dist_info_dir,
            pyc_touched,
        )


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        description="Extract a wheel into a TreeArtifact directory.",
        fromfile_prefix_chars="@",
    )
    parser.add_argument("--wheel", type=Path, required=True)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument(
        "--target-os",
        choices=["unix", "windows"],
        default="unix",
    )
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
    parser.add_argument(
        "--create-namespace-inits",
        action="store_true",
        default=False,
    )
    parser.add_argument(
        "--precompile",
        action="store_true",
        default=False,
    )
    parser.add_argument(
        "--pyc-tag",
        default="",
    )
    parser.add_argument(
        "--precompile-invalidation-mode",
        choices=["checked_hash", "unchecked_hash"],
        default="checked_hash",
    )
    parser.add_argument(
        "--precompile-optimize-level",
        type=int,
        default=0,
    )
    parser.add_argument(
        "--precompile-source-retention",
        choices=["keep_source", "omit_source"],
        default="keep_source",
    )
    parser.add_argument(
        "--python-version",
        default="",
    )
    parser.add_argument(
        "--src-name-prefix",
        default="",
    )
    parser.add_argument(
        "--precompiler-tool",
        type=Path,
        default=None,
    )
    args = parser.parse_args(argv)

    install_wheel(
        args.wheel,
        args.directory,
        target_os=args.target_os,
        srcs_exclude_globs=args.srcs_exclude_globs,
        data_exclude_globs=args.data_exclude_globs,
        create_namespace_inits_flag=args.create_namespace_inits,
        precompile=args.precompile,
        pyc_tag=args.pyc_tag,
        precompile_invalidation_mode=args.precompile_invalidation_mode,
        precompile_optimize_level=args.precompile_optimize_level,
        precompile_source_retention=args.precompile_source_retention,
        python_version=args.python_version,
        src_name_prefix=args.src_name_prefix,
        precompiler_tool=args.precompiler_tool,
    )


if __name__ == "__main__":
    main()

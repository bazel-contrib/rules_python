"""Build a Python wheel (.whl) from an sdist archive in a Bazel build action.

Extracts an input `.tar.gz`/`.tgz`/`.zip` sdist archive, applies optional
unified-diff patches, stages `build_deps` and PEP 517 bootstrap wheels onto
`PYTHONPATH`, builds the wheel in `--out-wheel-dir`, and copies it to
`--out-wheel-file`.

Usage:
    python3 -B sdist_wheel_builder.py --sdist path/to/pkg-1.0.tar.gz \\
        --out-wheel-dir path/to/pkg.whldir \\
        --out-wheel-file path/to/pkg.sdist_build.whl
"""

from __future__ import annotations

import argparse
import importlib.metadata
import os
import platform
import shlex
import shutil
import subprocess
import sys
import sysconfig
import tarfile
import zipfile
from pathlib import Path

from wheel_layout import (
    apply_unified_patch,
    sanitize_wheel_entry_path,
    single_wheel_in,
)
from wheel_transformer import scrub_bazel_env


def _detect_host_os() -> str:
    if sys.platform.startswith("linux"):
        return "linux"
    if sys.platform == "darwin":
        return "macos"
    if sys.platform in ("win32", "cygwin", "msys"):
        return "windows"
    return sys.platform


def _detect_host_cpu() -> str:
    machine = platform.machine().lower()
    if machine in ("x86_64", "amd64"):
        return "x86_64"
    if machine in ("aarch64", "arm64", "arm64e"):
        return "aarch64"
    if machine in ("i386", "i686", "x86", "x86_32"):
        return "x86_32"
    if machine.startswith("arm"):
        return "arm"
    if machine in ("ppc64le", "ppc64", "ppc"):
        return "ppc"
    return machine


def _extract_sdist(sdist_path: Path, extract_dir: Path) -> Path:
    extract_dir.mkdir(parents=True, exist_ok=True)
    if zipfile.is_zipfile(sdist_path):
        with zipfile.ZipFile(sdist_path) as zf:
            for info in zf.infolist():
                parts = sanitize_wheel_entry_path(info.filename)
                if parts is None:
                    continue
                target_path = extract_dir / "/".join(parts)
                target_path.parent.mkdir(parents=True, exist_ok=True)
                with zf.open(info) as src_f, open(target_path, "wb") as dst_f:
                    shutil.copyfileobj(src_f, dst_f)
                unix_mode = (info.external_attr >> 16) & 0o777
                if unix_mode:
                    os.chmod(target_path, unix_mode | 0o600)
    else:
        with tarfile.open(sdist_path, "r:*") as tf:
            try:
                tf.extractall(extract_dir, filter="data")
            except TypeError as exc:
                raise RuntimeError(
                    "Python interpreter does not support tarfile.extractall(filter='data'); "
                    "Python 3.11.4+ / 3.10.12+ is required"
                ) from exc

    children = [p for p in extract_dir.iterdir() if not p.name.startswith(".")]
    if len(children) == 1 and children[0].is_dir():
        return children[0]
    return extract_dir


def _resolve_wheel_and_bootstrap_paths(
    prefix: Path,
    installed_wheel_dirs: list[str],
    raw_python_paths: list[str],
) -> tuple[list[str], list[str], list[Path]]:
    """Resolve `--installed-wheel-dir` and `--python-path` arguments."""
    wheel_py: list[str] = []
    bootstrap_py: list[str] = []
    bin_dirs: list[Path] = []
    for wd in installed_wheel_dirs:
        wd_abs = (prefix / wd).absolute()
        sp_abs = wd_abs / "site-packages"
        if sp_abs.is_dir():
            wheel_py.append(str(sp_abs))
            bin_abs = wd_abs / "bin"
            if bin_abs.is_dir():
                bin_dirs.append(bin_abs)
    for raw_p in raw_python_paths:
        bootstrap_py.append(str((prefix / raw_p).absolute()))
    return wheel_py, bootstrap_py, bin_dirs


def _stage_dep_files(
    deps_dir: Path,
    prefix: Path,
    workspace_name: str,
    import_roots: list[str],
    dep_files: list[str],
    existing_py_paths: list[str] | tuple[str, ...] = (),
) -> tuple[list[str], list[str]]:
    """Stage non-wheel `build_deps` files by runfiles path into `deps_dir`."""
    if not dep_files and not import_roots:
        return [], []
    if dep_files:
        deps_dir.mkdir(parents=True, exist_ok=True)
    ws = workspace_name.replace("\\", "/").strip("/") or "_main"
    staged_sources: dict[Path, Path] = {}

    for entry in dep_files:
        exec_rel, sep, short_rel = entry.partition("=")
        if not sep or not exec_rel or not short_rel:
            continue
        src_abs = (prefix / exec_rel).absolute()
        norm_short = short_rel.replace("\\", "/").lstrip("/")
        runfiles_rel = (
            norm_short[3:] if norm_short.startswith("../") else f"{ws}/{norm_short}"
        )
        parts = sanitize_wheel_entry_path(runfiles_rel)
        if not parts:
            continue
        dest_path = deps_dir.joinpath(*parts)
        src_resolved = src_abs.resolve()
        prev_src = staged_sources.get(dest_path)
        if prev_src is not None:
            if prev_src != src_resolved:
                raise ValueError(
                    f"Conflicting build_deps files map to the same path "
                    f"'{runfiles_rel}': '{prev_src}' vs '{src_resolved}'"
                )
            continue
        staged_sources[dest_path] = src_resolved
        dest_path.parent.mkdir(parents=True, exist_ok=True)
        if not dest_path.exists() and not dest_path.is_symlink():
            try:
                dest_path.symlink_to(src_abs)
            except OSError:
                shutil.copy2(src_abs, dest_path)

    norm_roots = [
        imp.replace("\\", "/").strip("/")
        for imp in import_roots
        if imp.replace("\\", "/").strip("/")
    ]
    existing_norm = [p.replace("\\", "/").rstrip("/") for p in existing_py_paths]
    matched_roots: list[str] = []
    unmatched_roots: list[tuple[str, Path]] = []
    site_pkg_imports: list[str] = []
    first_party_imports: list[str] = []

    for norm_imp in norm_roots:
        imp_dir = (deps_dir / norm_imp).absolute()
        if imp_dir.is_dir():
            matched_roots.append(norm_imp)
            imp_str = str(imp_dir)
            if norm_imp == "site-packages" or norm_imp.endswith("/site-packages"):
                if imp_str not in site_pkg_imports:
                    site_pkg_imports.append(imp_str)
            elif imp_str not in first_party_imports:
                first_party_imports.append(imp_str)
        else:
            unmatched_roots.append((norm_imp, imp_dir))

    for norm_imp, imp_dir in unmatched_roots:
        # In venvs_site_packages=yes mode, py_library populates PyInfo.imports with
        # raw unprefixed imports alongside the resolved PyInfo.venv_symlinks root.
        if any(m.endswith(f"/{norm_imp}") for m in matched_roots):
            continue
        # Transitive PyInfo.imports from a py_library depending on an installed wheel
        # or bootstrap library are already present in existing_py_paths.
        rel_imp = norm_imp[len(ws) + 1 :] if norm_imp.startswith(f"{ws}/") else norm_imp
        if "/" in rel_imp and any(ep.endswith(f"/{rel_imp}") for ep in existing_norm):
            continue
        raise ValueError(
            f"Import root '{norm_imp}' does not exist under staged build_deps ({imp_dir})"
        )

    ws_dir = (deps_dir / ws).absolute()
    if ws_dir.is_dir() and str(ws_dir) not in first_party_imports:
        first_party_imports.append(str(ws_dir))

    return site_pkg_imports, first_party_imports


def _populate_scratch_bin_dir(
    scratch_bin_dir: Path,
    build_python: str,
    bin_dirs: list[Path],
    python_paths: list[str],
) -> None:
    """Create a tool bin directory containing python3/python and build_deps console scripts."""
    scratch_bin_dir.mkdir(parents=True, exist_ok=True)
    build_py_abs = Path(build_python).absolute()

    for link_name in ("python3", "python"):
        dest = scratch_bin_dir / link_name
        if not dest.exists() and not dest.is_symlink():
            dest.symlink_to(build_py_abs)

    for bd_abs in bin_dirs:
        for item in sorted(bd_abs.iterdir()):
            if not item.is_file():
                continue
            dest = scratch_bin_dir / item.name
            if dest.exists():
                continue
            shutil.copy2(item, dest)
            os.chmod(dest, os.stat(dest).st_mode | 0o755)

    for dist in importlib.metadata.distributions(path=python_paths):
        for ep in dist.entry_points:
            if ep.group not in ("console_scripts", "gui_scripts"):
                continue
            dest = scratch_bin_dir / ep.name
            if dest.exists():
                continue
            module_name, sep, attr_name = (
                ep.value.partition("[")[0].strip().partition(":")
            )
            if not sep or not module_name or not attr_name:
                continue
            with open(dest, "w", encoding="utf-8", newline="\n") as f:
                f.write(
                    "#!/bin/sh\n"
                    '\'\'\'exec\' "$(dirname "$0")/python3" "$0" "$@"\n'
                    "' '''\n"
                    f"import re, sys\nfrom {module_name.strip()} import {attr_name.strip()}\n"
                    "if __name__ == '__main__':\n"
                    "    sys.argv[0] = re.sub(r'(-script\\.pyw|\\.exe)?$', '', sys.argv[0])\n"
                    f"    sys.exit({attr_name.strip()}())\n"
                )
            os.chmod(dest, 0o755)


def _get_macos_sysroot_cflag() -> str:
    """Query macOS SDK path via xcrun for python-build-standalone compatibility."""
    if sys.platform != "darwin":
        return ""
    xcrun = shutil.which("xcrun")
    if not xcrun:
        return ""
    proc = subprocess.run(
        [xcrun, "--show-sdk-path"],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode == 0 and proc.stdout.strip():
        return f"-isysroot {proc.stdout.strip()}"
    return ""


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build a wheel from an sdist archive into a TreeArtifact directory.",
        fromfile_prefix_chars="@",
    )
    parser.add_argument("--sdist", type=Path, required=True)
    parser.add_argument("--wheel-dir", type=Path, required=True)
    parser.add_argument("--out-wheel-file", type=Path, default=None)
    parser.add_argument("--workspace-name", default="_main")
    parser.add_argument(
        "--installed-wheel-dir",
        action="append",
        dest="installed_wheel_dirs",
        default=[],
    )
    parser.add_argument(
        "--python-path",
        action="append",
        dest="python_paths",
        default=[],
    )
    parser.add_argument(
        "--import-root",
        action="append",
        dest="import_roots",
        default=[],
    )
    parser.add_argument(
        "--dep-file",
        action="append",
        dest="dep_files",
        default=[],
    )
    parser.add_argument(
        "--config-setting",
        action="append",
        dest="config_settings",
        default=[],
    )
    parser.add_argument(
        "--env",
        action="append",
        dest="env_vars",
        default=[],
    )
    parser.add_argument(
        "--patch",
        action="append",
        dest="patches",
        default=[],
    )
    parser.add_argument(
        "--add-libdir-to-library-search-path",
        action="store_true",
        default=False,
    )
    parser.add_argument("--target-os", default="")
    parser.add_argument("--target-cpu", default="")
    parser.add_argument("--target-python-version", default="")
    parser.add_argument("--cc", default="")
    parser.add_argument("--cxx", default="")
    parser.add_argument("--ar", default="")
    parser.add_argument("--cflag", action="append", dest="cflags", default=[])
    parser.add_argument("--cxxflag", action="append", dest="cxxflags", default=[])
    parser.add_argument("--ldflag", action="append", dest="ldflags", default=[])
    parser.add_argument("--sysroot", default="")
    parser.add_argument("--target-python-bin", default="")
    parser.add_argument(
        "--target-python-include",
        action="append",
        dest="target_python_includes",
        default=[],
    )
    parser.add_argument("--target-soabi", default="")
    parser.add_argument("--target-platform-tag", default="")
    args = parser.parse_args()

    host_os = _detect_host_os()
    host_cpu = _detect_host_cpu()
    is_cross = bool(
        (args.target_os and args.target_os != host_os) or
        (args.target_cpu and args.target_cpu != host_cpu)
    )
    if is_cross and not args.cc:
        raise RuntimeError(
            f"Target platform (os={args.target_os or 'any'}, cpu={args.target_cpu or 'any'}) "
            f"differs from host (os={host_os}, cpu={host_cpu}); "
            "but no cross-compiler (--cc) was provided."
        )
    host_py_ver = f"{sys.version_info.major}.{sys.version_info.minor}"
    if args.target_python_version and args.target_python_version != host_py_ver:
        raise RuntimeError(
            f"Target Python version ({args.target_python_version}) differs from "
            f"build Python interpreter ({host_py_ver}); py_sdist_wheel requires "
            "matching major.minor versions."
        )

    prefix = Path.cwd().absolute()
    sdist_abs = (prefix / args.sdist).absolute()
    wheel_dir_abs = (prefix / args.wheel_dir).absolute()
    wheel_dir_abs.mkdir(parents=True, exist_ok=True)

    wheel_py_paths, bootstrap_py_paths, bin_dirs = _resolve_wheel_and_bootstrap_paths(
        prefix,
        args.installed_wheel_dirs,
        args.python_paths,
    )

    orig_env = scrub_bazel_env(os.environ.copy())
    build_python = sys.executable

    scratch_dir = (wheel_dir_abs.parent / f"_{wheel_dir_abs.name}_tmp").absolute()
    shutil.rmtree(scratch_dir, ignore_errors=True)

    try:
        home_dir = scratch_dir / "home"
        work_tmp_dir = scratch_dir / "tmp"
        scratch_bin_dir = scratch_dir / "bin"
        home_dir.mkdir(parents=True, exist_ok=True)
        work_tmp_dir.mkdir(parents=True, exist_ok=True)

        site_pkg_imports, first_party_imports = _stage_dep_files(
            deps_dir=scratch_dir / "deps",
            prefix=prefix,
            workspace_name=args.workspace_name,
            import_roots=args.import_roots,
            dep_files=args.dep_files,
            existing_py_paths=[
                *wheel_py_paths,
                *(f"{bp}/site-packages" for bp in bootstrap_py_paths),
            ],
        )
        resolved_python_paths = [
            *wheel_py_paths,
            *site_pkg_imports,
            *bootstrap_py_paths,
            *first_party_imports,
        ]

        _populate_scratch_bin_dir(
            scratch_bin_dir=scratch_bin_dir,
            build_python=build_python,
            bin_dirs=bin_dirs,
            python_paths=resolved_python_paths,
        )

        sdist_root = _extract_sdist(sdist_abs, scratch_dir / "src")
        for item in args.patches:
            raw_path, _, raw_strip = item.rpartition(":")
            apply_unified_patch(
                sdist_root,
                (prefix / Path(raw_path)).absolute(),
                strip=int(raw_strip),
            )

        def _resolve_tool(prefix: Path, raw: str) -> str:
            if not raw or os.path.isabs(raw):
                return raw
            candidate = (prefix / raw).absolute()
            return str(candidate) if candidate.exists() else raw

        env = dict(orig_env)
        env["PYTHONHASHSEED"] = "0"
        env["PYTHONNOUSERSITE"] = "1"
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        env.setdefault("SOURCE_DATE_EPOCH", "315532800")
        env["HOME"] = str(home_dir)
        env["TMPDIR"] = str(work_tmp_dir)
        env["TEMP"] = str(work_tmp_dir)
        env["TMP"] = str(work_tmp_dir)

        c_remap_flag = f"-ffile-prefix-map={scratch_dir}=."
        for flag_var in ("CFLAGS", "CXXFLAGS"):
            env[flag_var] = (
                f"{env[flag_var]} {c_remap_flag}" if env.get(flag_var) else c_remap_flag
            )

        rust_remap_flag = f"--remap-path-prefix={scratch_dir}=."
        env["RUSTFLAGS"] = (
            f"{env['RUSTFLAGS']} {rust_remap_flag}"
            if env.get("RUSTFLAGS")
            else rust_remap_flag
        )

        cc_bin = _resolve_tool(prefix, args.cc)
        cxx_bin = _resolve_tool(prefix, args.cxx)
        ar_bin = _resolve_tool(prefix, args.ar)
        if cc_bin:
            env["CC"] = cc_bin
            env["LDSHARED"] = f"{cc_bin} -shared"
        if cxx_bin:
            env["CXX"] = cxx_bin
            env["LDCXXSHARED"] = f"{cxx_bin} -shared"
        if ar_bin:
            env["AR"] = ar_bin
        if args.sysroot:
            sysroot_abs = _resolve_tool(prefix, args.sysroot)
            for var in ("CFLAGS", "CXXFLAGS", "LDFLAGS"):
                env[var] = (
                    f"{env[var]} --sysroot={sysroot_abs}"
                    if env.get(var) else f"--sysroot={sysroot_abs}"
                )

        # Because pip wheel runs with cwd=sdist_root (`scratch_dir/src/...`)
        # rather than the Bazel execroot, any execroot-relative paths
        # (`external/...`) in those flags need to be turned into absolute
        # paths (`prefix / ...`).

        def _absolutize_flag(prefix: Path, flag: str) -> str:
            if flag.startswith("-Wl,"):
                parts = flag[4:].split(",")
                new_parts = []
                for p in parts:
                    if p.startswith("-L") and len(p) > 2 and not os.path.isabs(p[2:]) and (prefix / p[2:]).exists():
                        new_parts.append("-L" + str((prefix / p[2:]).absolute()))
                    elif p and not p.startswith("-") and not os.path.isabs(p) and (prefix / p).exists():
                        new_parts.append(str((prefix / p).absolute()))
                    else:
                        new_parts.append(p)
                return "-Wl," + ",".join(new_parts)
            for opt in ("--sysroot=", "-resource-dir=", "-isystem", "-I", "-L", "-B"):
                if flag.startswith(opt) and len(flag) > len(opt):
                    rel = flag[len(opt):]
                    if not os.path.isabs(rel) and (prefix / rel).exists():
                        return opt + str((prefix / rel).absolute())
                    return flag
            if flag.startswith("-") and "=" in flag:
                key, _, rel = flag.partition("=")
                if "/" in rel and not os.path.isabs(rel) and (prefix / rel).exists():
                    return f"{key}={str((prefix / rel).absolute())}"
            if flag and not flag.startswith("-") and not os.path.isabs(flag) and (prefix / flag).exists():
                return str((prefix / flag).absolute())
            return flag

        link_resource_dirs = [f for f in args.ldflags if f.startswith("-resource-dir=")]
        redacted_prefixes = ("-D__DATE__=", "-D__TIMESTAMP__=", "-D__TIME__=")

        def _sanitize_compile_flags(flags: list[str]) -> list[str]:
            out = [f for f in flags if not f.startswith(redacted_prefixes)]
            if not link_resource_dirs:
                return out
            return [
                link_resource_dirs[-1] if f.startswith("-resource-dir=") else f
                for f in out
            ]

        for var, raw_flags in (
            ("CFLAGS", _sanitize_compile_flags(args.cflags)),
            ("CXXFLAGS", _sanitize_compile_flags(args.cxxflags)),
            ("LDFLAGS", [f for f in args.ldflags if f != "-shared"]),
        ):
            if raw_flags:
                resolved = " ".join(shlex.quote(_absolutize_flag(prefix, f)) for f in raw_flags)
                env[var] = f"{env[var]} {resolved}" if env.get(var) else resolved

        cppflags: list[str] = [env["CPPFLAGS"]] if env.get("CPPFLAGS") else []
        if args.target_python_includes:
            for inc in args.target_python_includes:
                inc_abs = str((prefix / inc).absolute())
                cppflags.append(f"-I{inc_abs}")
        else:
            include_dir = sysconfig.get_path("include") or ""
            if include_dir and os.path.isdir(include_dir):
                cppflags.append(f"-isystem {include_dir}")
        sysroot_flag = _get_macos_sysroot_cflag()
        if (
            sysroot_flag
            and "-isysroot" not in env.get("CPPFLAGS", "")
            and "-isysroot" not in env.get("CFLAGS", "")
        ):
            cppflags.append(sysroot_flag)
        if cppflags:
            env["CPPFLAGS"] = " ".join(cppflags)

        env["PYTHONPATH"] = os.pathsep.join(resolved_python_paths)
        orig_path = env.get("PATH", "")
        env["PATH"] = os.pathsep.join(
            [str(scratch_bin_dir)] + ([orig_path] if orig_path else [])
        )

        if args.add_libdir_to_library_search_path:
            libdir_flag = f"-L{sys.exec_prefix}/lib"
            env["LDFLAGS"] = (
                f"{env['LDFLAGS']} {libdir_flag}" if env.get("LDFLAGS") else libdir_flag
            )

        for item in args.env_vars:
            k, sep, v = item.partition("=")
            if not sep or not k:
                raise ValueError(f"Invalid --env entry '{item}', expected KEY=VALUE")
            env[k] = v

        pip_config_args = [f"--config-settings={cs}" for cs in args.config_settings]

        if is_cross:
            if args.target_os == "linux" and args.target_cpu:
                env["_PYTHON_HOST_PLATFORM"] = f"linux-{args.target_cpu}"
            if args.target_soabi:
                ext = ".pyd" if args.target_os == "windows" else ".so"
                env["SETUPTOOLS_EXT_SUFFIX"] = f".{args.target_soabi}{ext}"
            if args.target_python_bin and args.target_python_version:
                target_py_root = (prefix / args.target_python_bin).absolute().parent.parent
                target_stdlib = target_py_root / "lib" / f"python{args.target_python_version}"
                sysconfig_files = sorted(target_stdlib.glob("_sysconfigdata_*.py"))
                if sysconfig_files:
                    sc_src = sysconfig_files[0]
                    sc_dir = scratch_dir / "sysconfig"
                    sc_dir.mkdir(parents=True, exist_ok=True)
                    sc_text = sc_src.read_text(encoding="utf-8")
                    if args.target_python_includes:
                        inc_dirs = [
                            str((prefix / inc).absolute())
                            for inc in args.target_python_includes
                            if (prefix / inc / "Python.h").is_file()
                        ]
                        inc_abs = (
                            inc_dirs[0]
                            if inc_dirs
                            else str((prefix / args.target_python_includes[-1]).absolute())
                        )
                        sc_text += (
                            f"\nbuild_time_vars['INCLUDEPY'] = {inc_abs!r}\n"
                            f"build_time_vars['CONFINCLUDEPY'] = {inc_abs!r}\n"
                        )
                    (sc_dir / sc_src.name).write_text(sc_text, encoding="utf-8")
                    env["_PYTHON_SYSCONFIGDATA_NAME"] = sc_src.stem
                    resolved_python_paths.insert(0, str(sc_dir))
                    env["PYTHONPATH"] = os.pathsep.join(resolved_python_paths)

        pyproject_file = sdist_root / "pyproject.toml"
        if (is_cross and
                pyproject_file.is_file() and
                "mesonpy" in pyproject_file.read_text(errors="ignore")):
            cpu_family = {"x86_32": "x86"}.get(args.target_cpu, args.target_cpu)
            cross_ini = scratch_dir / "meson-cross.ini"
            cross_lines = [
                "[binaries]",
                f"c = {cc_bin!r}",
            ]
            if cxx_bin:
                cross_lines.append(f"cpp = {cxx_bin!r}")
            if ar_bin:
                meson_ar = ar_bin
                if "zig" in ar_bin or "zig" in cc_bin:
                    # zig-specific adjustment: zig's ar doesn't support thin
                    # archives.
                    ar_wrapper = scratch_bin_dir / "ar-no-thin"
                    ar_wrapper.write_text(
                        f"#!/usr/bin/env python3\n"
                        f"import os, sys\n"
                        f"args = sys.argv[1:]\n"
                        f"if args and not args[0].startswith('-'):\n"
                        f"    args[0] = args[0].replace('T', '')\n"
                        f"os.execv({ar_bin!r}, [{ar_bin!r}, *args])\n",
                        encoding="utf-8",
                    )
                    os.chmod(ar_wrapper, 0o755)
                    meson_ar = str(ar_wrapper)
                cross_lines.append(f"ar = {meson_ar!r}")
            cross_lines += [
                "",
                "[host_machine]",
                f"system = {args.target_os!r}",
                f"cpu_family = {cpu_family!r}",
                f"cpu = {args.target_cpu!r}",
                "endian = 'little'",
            ]
            longdouble_formats = {
                ("linux", "aarch64"): "IEEE_QUAD_LE",
                ("linux", "x86_64"): "INTEL_EXTENDED_16_BYTES_LE",
                ("linux", "x86_32"): "INTEL_EXTENDED_12_BYTES_LE",
                ("macos", "aarch64"): "IEEE_DOUBLE_LE",
                ("macos", "x86_64"): "INTEL_EXTENDED_16_BYTES_LE",
                ("windows", "aarch64"): "IEEE_DOUBLE_LE",
                ("windows", "x86_64"): "IEEE_DOUBLE_LE",
            }
            ld_fmt = longdouble_formats.get((args.target_os, args.target_cpu))
            if ld_fmt:
                cross_lines += [
                    "",
                    "[properties]",
                    f"longdouble_format = {ld_fmt!r}",
                ]
            cross_ini.write_text("\n".join(cross_lines) + "\n", encoding="utf-8")
            pip_config_args.append(f"--config-settings=setup-args=--cross-file={cross_ini}")

        cmd = [
            build_python,
            "-m",
            "pip",
            "--isolated",
            "--no-cache-dir",
            "wheel",
            "--no-deps",
            "--no-index",
            "--no-build-isolation",
            "--check-build-dependencies",
            "--wheel-dir",
            str(wheel_dir_abs),
            *pip_config_args,
            str(sdist_root.absolute()),
        ]
        result = subprocess.run(
            cmd,
            env=env,
            cwd=str(sdist_root),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        if result.returncode != 0:
            hint = ""
            if (
                "Some build dependencies" in result.stdout
                and "are missing" in result.stdout
            ):
                hint = (
                    "\nHint: Ensure the missing build requirements are present in your "
                    "pip requirements lockfile / hub or specify them via "
                    "'sdist_build_deps' (pip.whl_mods / package_annotation) or "
                    "'py_sdist_wheel.build_deps'."
                )
            sys.stderr.write(
                f"Failed to build wheel from sdist '{args.sdist}':\n{result.stdout}{hint}\n"
            )
            sys.exit(result.returncode)
    finally:
        shutil.rmtree(scratch_dir, ignore_errors=True)

    built_whl = single_wheel_in(wheel_dir_abs)
    if args.out_wheel_file is not None:
        out_whl_abs = (prefix / args.out_wheel_file).absolute()
        if out_whl_abs.exists() or out_whl_abs.is_symlink():
            out_whl_abs.unlink()
        try:
            os.link(built_whl, out_whl_abs)
        except OSError:
            shutil.copy2(built_whl, out_whl_abs)


if __name__ == "__main__":
    main()

# Copyright 2024 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""site initialization logic for Bazel-built py_binary targets."""

import os
import os.path
import sys

# Colon-delimited string of runfiles-relative import paths to add
_IMPORTS_STR = "%imports%"
# Though the import all value is the correct literal, we quote it
# so this file is parsable by tools.
_IMPORT_ALL = "%import_all%" == "True"
_WORKSPACE_NAME = "%workspace_name%"
# runfiles-relative path to this file
_SELF_RUNFILES_RELATIVE_PATH = "%site_init_runfiles_path%"
# Runfiles-relative path to the coverage tool entry point, if any.
_COVERAGE_TOOL = "%coverage_tool%"
# True if the runfiles root should be added to sys.path
_ADD_RUNFILES_ROOT_TO_SYS_PATH = "%add_runfiles_root_to_sys_path%" == "1"
_INTERPRETER_ACTUAL_PATH = "%interpreter_actual_path%"


def _is_verbose():
    return bool(os.environ.get("RULES_PYTHON_BOOTSTRAP_VERBOSE"))


def _print_verbose_coverage(*args):
    if os.environ.get("VERBOSE_COVERAGE") or _is_verbose():
        _print_verbose(*args)


def _print_verbose(*args, mapping=None, values=None):
    if not _is_verbose():
        return

    print("bazel_site_init:", *args, file=sys.stderr, flush=True)


_print_verbose("imports_str:", _IMPORTS_STR)
_print_verbose("import_all:", _IMPORT_ALL)
_print_verbose("workspace_name:", _WORKSPACE_NAME)
_print_verbose("self_runfiles_path:", _SELF_RUNFILES_RELATIVE_PATH)
_print_verbose("coverage_tool:", _COVERAGE_TOOL)
_print_verbose("interpreter_actual_path:", _INTERPRETER_ACTUAL_PATH)


def _find_runfiles_root():
    # Give preference to the environment variables
    runfiles_dir = os.environ.get("RUNFILES_DIR", None)
    if not runfiles_dir:
        runfiles_manifest_file = os.environ.get("RUNFILES_MANIFEST_FILE", "")
        if runfiles_manifest_file.endswith(
            ".runfiles_manifest"
        ) or runfiles_manifest_file.endswith(".runfiles/MANIFEST"):
            runfiles_dir = runfiles_manifest_file[:-9]

    # Be defensive: the runfiles dir should contain ourselves. If it doesn't,
    # then it must not be our runfiles directory.
    if runfiles_dir and os.path.exists(
        os.path.join(runfiles_dir, _SELF_RUNFILES_RELATIVE_PATH)
    ):
        return runfiles_dir

    num_dirs_to_runfiles_root = _SELF_RUNFILES_RELATIVE_PATH.count("/") + 1
    runfiles_root = os.path.dirname(__file__)
    for _ in range(num_dirs_to_runfiles_root):
        runfiles_root = os.path.dirname(runfiles_root)
    return runfiles_root


_RUNFILES_ROOT = _find_runfiles_root()

_print_verbose("runfiles_root:", _RUNFILES_ROOT)


def _is_windows():
    return os.name == "nt"


def _get_windows_path_with_unc_prefix(path):
    path = path.strip()
    # No need to add prefix for non-Windows platforms.
    if not _is_windows() or sys.version_info[0] < 3:
        return path

    # import sysconfig only now to maintain python 2.6 compatibility
    import sysconfig

    if sysconfig.get_platform() == "mingw":
        return path

    # Implicit long-path support is not universal across the Win32 API. For
    # example, DLL loading still requires an explicit extended-length prefix.
    extended_path_prefix = "\\\\?\\"
    if path.startswith(extended_path_prefix):
        return path

    # os.path.abspath returns a normalized absolute path
    path = os.path.abspath(path)
    if path.startswith("\\\\"):
        return extended_path_prefix + "UNC\\" + path[2:]
    return extended_path_prefix + path


def _install_windows_extension_finder():
    """Use extended-length paths when loading long Windows extension paths."""
    if not _is_windows() or sys.version_info[0] < 3:
        return

    # import these only now to maintain Python 2.6 compatibility
    import importlib.machinery
    import sysconfig

    if sysconfig.get_platform() == "mingw":
        return

    class _WindowsExtensionPathFinder(importlib.machinery.PathFinder):
        @classmethod
        def find_spec(cls, fullname, path=None, target=None):
            spec = super().find_spec(fullname, path, target)
            if (
                spec is None
                or not isinstance(spec.loader, importlib.machinery.ExtensionFileLoader)
                or len(os.path.abspath(spec.origin)) < 260
            ):
                return spec

            # The registry opt-in for long paths only applies to documented
            # file and directory APIs. It does not include DLL loading APIs,
            # e.g. LoadLibraryExW. Prefix the actual extension filename instead
            # of sys.path entries so other APIs continue to receive normal paths.
            # https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation#functions-without-max_path-restrictions
            extended_path = _get_windows_path_with_unc_prefix(spec.origin)
            spec.origin = extended_path
            spec.loader.path = extended_path
            return spec

    for index, finder in enumerate(sys.meta_path):
        if finder is importlib.machinery.PathFinder:
            sys.meta_path[index] = _WindowsExtensionPathFinder
            return


def _search_path(name):
    """Finds a file in a given search path."""
    search_path = os.getenv("PATH", os.defpath).split(os.pathsep)
    for directory in search_path:
        if directory:
            path = os.path.join(directory, name)
            if os.path.isfile(path) and os.access(path, os.X_OK):
                return path
    return None


def _setup_sys_path():
    """Perform Bazel/binary specific sys.path setup."""
    _print_verbose("site init: initial sys.path:\n", "\n".join(sys.path))
    seen = set(sys.path)

    def _maybe_add_path(path, reason):
        if path in seen:
            return
        if _is_windows():
            path = path.replace("/", os.sep)

        _print_verbose("append sys.path:", reason, ":", path)
        sys.path.append(path)
        seen.add(path)

    # Adding the runfiles root to sys.path is a legacy behavior that will be
    # removed. We don't want to add it to sys.path for two reasons:
    # 1. Under workspace, it makes every external repository importable. If a Bazel
    #    repository matches a Python import name, they conflict.
    # 2. Under bzlmod, the repo names in the runfiles directory aren't importable
    #    Python names, so there's no point in adding the runfiles root to sys.path.
    # For temporary compatibility with the original system_python bootstrap
    # behavior, it is conditionally added for that boostrap mode.
    if _ADD_RUNFILES_ROOT_TO_SYS_PATH:
        _maybe_add_path(_RUNFILES_ROOT, "runfiles-root")

    for rel_path in _IMPORTS_STR.split(":"):
        abs_path = os.path.join(_RUNFILES_ROOT, rel_path)
        _maybe_add_path(abs_path, "imports-strs")

    if _IMPORT_ALL:
        repo_dirs = sorted(
            os.path.join(_RUNFILES_ROOT, d) for d in os.listdir(_RUNFILES_ROOT)
        )
        for d in repo_dirs:
            if os.path.isdir(d):
                _maybe_add_path(d, "import-all")
    else:
        _maybe_add_path(os.path.join(_RUNFILES_ROOT, _WORKSPACE_NAME), "workspace-root")

    # COVERAGE_DIR is set if coverage is enabled and instrumentation is configured
    # for something, though it could be another program executing this one or
    # one executed by this one (e.g. an extension module).
    # NOTE: Coverage is added last to allow user dependencies to override it.
    coverage_setup = False
    if os.environ.get("COVERAGE_DIR"):
        cov_tool = _COVERAGE_TOOL
        if cov_tool:
            _print_verbose_coverage(f"Using toolchain coverage_tool {cov_tool}")
        elif cov_tool := os.environ.get("PYTHON_COVERAGE"):
            _print_verbose_coverage(
                f"Using env var coverage: PYTHON_COVERAGE={cov_tool}"
            )

        if cov_tool:
            if os.path.isabs(cov_tool):
                pass
            elif os.sep in os.path.normpath(cov_tool):
                cov_tool = os.path.join(_RUNFILES_ROOT, cov_tool)
            else:
                cov_tool = _search_path(cov_tool)
        if cov_tool:
            # The coverage entry point is `<dir>/coverage/coverage_main.py`, so
            # we need to do twice the dirname so that `import coverage` works
            coverage_dir = os.path.dirname(os.path.dirname(cov_tool))

            # coverage library expects sys.path[0] to contain the library, and replaces
            # it with the directory of the program it starts. Our actual sys.path[0] is
            # the runfiles directory, which must not be replaced.
            # CoverageScript.do_execute() undoes this sys.path[0] setting.
            _maybe_add_path(coverage_dir, "coverage-dir")
            coverage_setup = True
        else:
            _print_verbose_coverage(
                "Coverage was enabled, but the coverage tool was not found or valid. "
                + "To enable coverage, consult the docs at "
                + "https://rules-python.readthedocs.io/en/latest/coverage.html"
            )

    return coverage_setup


def _fixup_sys_base_executable():
    """Fixup sys._base_executable to account for Bazel-specific pyvenv.cfg

    The pyvenv.cfg created for py_binary leaves the `home` key unset. A
    side-effect of this is `sys._base_executable` points to the venv executable,
    not the actual executable. This mostly doesn't matter, but does affect
    using the venv module to create venvs (they point to the venv executable, not
    the actual executable).
    """
    # Must have been set correctly?
    if sys.executable != sys._base_executable:
        return
    # Not in a venv, so don't touch anything.
    if sys.prefix == sys.base_prefix:
        return
    exe = os.path.realpath(sys.executable)
    _print_verbose("setting sys._base_executable:", exe)
    sys._base_executable = exe


def _fixup_stdlib_paths():
    """Remap non-runfiles runtime paths to their runfiles locations.

    Replaces non-runfiles sys prefix roots (e.g. sys.base_prefix) with the
    runtime root inside runfiles across sys.path, sys prefixes, and
    site.PREFIXES.
    """
    if not _INTERPRETER_ACTUAL_PATH or os.path.isabs(_INTERPRETER_ACTUAL_PATH):
        return
    if not _RUNFILES_ROOT:
        return

    def _norm_path(path_str):
        return os.path.normcase(path_str).replace("\\", "/").rstrip("/")

    abs_interpreter = os.path.join(_RUNFILES_ROOT, _INTERPRETER_ACTUAL_PATH)
    parent = os.path.dirname(abs_interpreter)
    if os.path.basename(parent).lower() in ("bin", "scripts"):
        runtime_root = os.path.dirname(parent)
    else:
        runtime_root = parent

    runfiles_norm = _norm_path(_RUNFILES_ROOT)
    runfiles_prefix = runfiles_norm + "/"

    def _in_runfiles(path_str):
        norm = _norm_path(path_str)
        return norm == runfiles_norm or norm.startswith(runfiles_prefix)

    target_root = os.path.abspath(runtime_root)
    if _is_windows():
        target_root = target_root.replace("/", os.sep)

    # When running in a virtual environment (sys.prefix != sys.base_prefix),
    # sys.prefix points to the .venv directory (which on Windows may reside
    # outside the runfiles tree). Never overwrite sys.prefix / sys.exec_prefix
    # with the base Python stdlib root in a venv.
    in_venv = sys.prefix != sys.base_prefix
    if in_venv:
        attrs = ("base_prefix", "base_exec_prefix")
    else:
        attrs = ("base_prefix", "base_exec_prefix", "prefix", "exec_prefix")

    candidate_prefixes = {}
    for attr in attrs:
        old_prefix = getattr(sys, attr)
        if not _in_runfiles(old_prefix):
            candidate_prefixes[attr] = old_prefix

    if not candidate_prefixes:
        return

    # First, verify if any candidate prefix has matching paths that physically
    # exist in the runfiles tree.
    remapped_prefixes = set()
    for p in sys.path:
        norm_p = _norm_path(p)
        for old_prefix in candidate_prefixes.values():
            norm_old = _norm_path(old_prefix)
            if norm_p == norm_old or norm_p.startswith(norm_old + "/"):
                candidate = target_root + p[len(old_prefix) :]
                if os.path.exists(candidate):
                    remapped_prefixes.add(old_prefix)
                    break

    if not remapped_prefixes:
        return

    # Remap all sys.path entries under the verified prefixes (including default
    # CPython virtual paths like pythonXY.zip that may not exist on disk).
    new_sys_path = []
    for p in sys.path:
        norm_p = _norm_path(p)
        matched = False
        for old_prefix in remapped_prefixes:
            norm_old = _norm_path(old_prefix)
            if norm_p == norm_old:
                # Omit the bare runtime root from early stdlib sys.path
                # positions;
                # Bazel's _setup_sys_path adds it under user imports.
                matched = True
                _print_verbose("omit bare stdlib root from early sys.path:", p)
                break
            elif norm_p.startswith(norm_old + "/"):
                new_path = target_root + p[len(old_prefix) :]
                _print_verbose("remap stdlib sys.path:", p, "->", new_path)
                new_sys_path.append(new_path)
                matched = True
                break
        if not matched:
            new_sys_path.append(p)
    sys.path[:] = new_sys_path

    if _is_windows():
        base_dlls = os.path.join(target_root, "DLLs")
        if os.path.exists(base_dlls):
            if base_dlls not in sys.path:
                insert_idx = 0
                for i, p in enumerate(sys.path):
                    if p.endswith(".zip"):
                        insert_idx = i + 1
                        break
                sys.path.insert(insert_idx, base_dlls)
            if hasattr(os, "add_dll_directory"):
                try:
                    os.add_dll_directory(base_dlls)
                except OSError:
                    pass

    for attr, old_prefix in candidate_prefixes.items():
        if old_prefix in remapped_prefixes:
            _print_verbose(f"remap sys.{attr}:", old_prefix, "->", target_root)
            setattr(sys, attr, target_root)

    import site

    if hasattr(site, "PREFIXES"):
        for i, prefix in enumerate(site.PREFIXES):
            if not _in_runfiles(prefix) and prefix in remapped_prefixes:
                _print_verbose("remap site.PREFIXES:", prefix, "->", target_root)
                site.PREFIXES[i] = target_root


_fixup_sys_base_executable()
_fixup_stdlib_paths()

COVERAGE_SETUP = _setup_sys_path()
_install_windows_extension_finder()
_print_verbose("DONE")

# Template for the __main__.py file inserted into zip files
#
# Generated file from @rules_python//python/private/zipapp:zip_main_template.py
#
# NOTE: This file is a "stage 1" bootstrap, so it's responsible for locating the
# desired runtime and having it run the stage 2 bootstrap. This means it can't
# assume much about the current runtime and environment. e.g., the current
# runtime may not be the correct one, the zip may not have been extracted, the
# runfiles env vars may not be set, etc.
#
# NOTE: This program must retain compatibility with a wide variety of Python
# versions since it is run by an unknown Python interpreter.
#
# NOTE: For a self-executable zip, this file may not be the entry point
# for the program and may be skipped entirely; the self-executable zip
# preamble may jump directly to the stage2 bootstrap.

import sys

# The Python interpreter unconditionally prepends the directory containing this
# script (following symlinks) to the import path. This is the cause of #9239,
# and is a special case of #7091. We therefore explicitly delete that entry.
# TODO(#7091): Remove this hack when no longer necessary.
del sys.path[0]

import os
import shutil
import stat
import subprocess
import tempfile
import zipfile
from os.path import basename, dirname, join

# runfiles-root-relative path
_STAGE2_BOOTSTRAP = "%stage2_bootstrap%"
# runfiles-root-relative path to venv's bin/python3. Empty if venv not being used.
_PYTHON_BINARY_VENV = "%python_binary%"
# runfiles-root-relative path, absolute path, or single word. The actual Python
# executable to use.
_PYTHON_BINARY_ACTUAL = "%python_binary_actual%"
_WORKSPACE_NAME = "%workspace_name%"
# relative path under EXTRACT_ROOT to extract to.
EXTRACT_DIR = "%EXTRACT_DIR%"
APP_HASH = "%APP_HASH%"

EXTRACT_ROOT = os.environ.get("RULES_PYTHON_EXTRACT_ROOT")
IS_WINDOWS = os.name == "nt"


EXTRACT_ROOT = os.environ.get("RULES_PYTHON_EXTRACT_ROOT")

# Change the paths with Unix-style forward slashes to backslashes for Windows.
# Windows usually transparently rewrites them, but e.g. `\\?\` paths require
# backslashes to be properly understood by Windows APIs.
if IS_WINDOWS:

    def norm_slashes(s):
        if not s:
            return s
        return s.replace("/", "\\")

    _STAGE2_BOOTSTRAP = norm_slashes(_STAGE2_BOOTSTRAP)
    _PYTHON_BINARY_VENV = norm_slashes(_PYTHON_BINARY_VENV)
    _PYTHON_BINARY_ACTUAL = norm_slashes(_PYTHON_BINARY_ACTUAL)
    EXTRACT_DIR = norm_slashes(EXTRACT_DIR)
    EXTRACT_ROOT = norm_slashes(EXTRACT_ROOT)


def print_verbose(*args, mapping=None, values=None):
    if not bool(os.environ.get("RULES_PYTHON_BOOTSTRAP_VERBOSE")):
        return
    if mapping is not None:
        for key, value in sorted((mapping or {}).items()):
            print(
                "bootstrap: stage 1:",
                *args,
                f"{key}={value!r}",
                file=sys.stderr,
                flush=True,
            )
    elif values is not None:
        for i, v in enumerate(values):
            print(
                "bootstrap: stage 1:",
                *args,
                f"[{i}] {v!r}",
                file=sys.stderr,
                flush=True,
            )
    else:
        print("bootstrap: stage 1:", *args, file=sys.stderr, flush=True)


def get_windows_path_with_unc_prefix(path):
    """Adds UNC prefix after getting a normalized absolute Windows path.

    No-op for non-Windows platforms or if running under python2.
    """
    path = path.strip()

    # No need to add prefix for non-Windows platforms.
    # And \\?\ doesn't work in python 2 or on mingw
    if not IS_WINDOWS or sys.version_info[0] < 3:
        return path

    # Starting in Windows 10, version 1607(OS build 14393), MAX_PATH limitations have been
    # removed from common Win32 file and directory functions.
    # Related doc: https://docs.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation?tabs=cmd#enable-long-paths-in-windows-10-version-1607-and-later
    import platform

    if platform.win32_ver()[1] >= "10.0.14393":
        return path

    # import sysconfig only now to maintain python 2.6 compatibility
    import sysconfig

    if sysconfig.get_platform() == "mingw":
        return path

    # Lets start the unicode fun
    unicode_prefix = "\\\\?\\"
    if path.startswith(unicode_prefix):
        return path

    # os.path.abspath returns a normalized absolute path
    return unicode_prefix + os.path.abspath(path)


def search_path(name):
    """Finds a file in a given search path."""
    search_path = os.getenv("PATH", os.defpath).split(os.pathsep)
    for directory in search_path:
        if directory:
            path = join(directory, name)
            if os.path.isfile(path) and os.access(path, os.X_OK):
                return path
    return None


def find_binary(runfiles_root, bin_name):
    """Finds the real binary if it's not a normal absolute path."""
    if not bin_name:
        return None
    if bin_name.startswith("//"):
        # Case 1: Path is a label. Not supported yet.
        raise AssertionError(
            "Bazel does not support execution of Python interpreters via labels"
        )
    elif os.path.isabs(bin_name):
        # Case 2: Absolute path.
        return bin_name
    # Use normpath() to convert slashes to os.sep on Windows.
    elif os.sep in os.path.normpath(bin_name):
        # Case 3: Path is relative to the repo root.
        return join(runfiles_root, bin_name)
    else:
        # Case 4: Path has to be looked up in the search path.
        return search_path(bin_name)


def extract_zip(zip_path, dest_dir):
    """Extracts the contents of a zip file, preserving the unix file mode bits.

    These include the permission bits, and in particular, the executable bit.

    Ideally the zipfile module should set these bits, but it doesn't. See:
    https://bugs.python.org/issue15795.

    Args:
        zip_path: The path to the zip file to extract
        dest_dir: The path to the destination directory
    """
    zip_path = get_windows_path_with_unc_prefix(zip_path)
    dest_dir = get_windows_path_with_unc_prefix(dest_dir)
    with zipfile.ZipFile(zip_path) as zf:
        for info in zf.infolist():
            file_path = os.path.abspath(join(dest_dir, info.filename))
            # If the file exists, it might be a symlink or read-only file from a previous extraction.
            # Unlink it first so zipfile.extract doesn't corrupt the symlink target or fail on read-only files.
            if os.path.lexists(file_path) and not os.path.isdir(file_path):
                try:
                    os.unlink(file_path)
                except OSError:
                    # On Windows, unlinking a read-only file fails.
                    os.chmod(file_path, stat.S_IWRITE)
                    os.unlink(file_path)

            zf.extract(info, dest_dir)
            # The Unix st_mode bits (see "man 7 inode") are stored in the upper 16
            # bits of external_attr.
            attrs = info.external_attr >> 16
            # Symlink bit in st_mode is 0o120000.
            if (attrs & 0o170000) == 0o120000:
                with open(file_path, "r") as f:
                    target = f.read()
                os.remove(file_path)
                os.symlink(target, file_path)
            # Of those, we set the lower 12 bits, which are the
            # file mode bits (since the file type bits can't be set by chmod anyway).
            elif attrs != 0:  # Rumor has it these can be 0 for zips created on Windows.
                os.chmod(file_path, attrs & 0o7777)


# Create the runfiles tree by extracting the zip file
def create_runfiles_root():
    if EXTRACT_ROOT:
        # Shorten the path for Windows in case long path support is disabled
        if IS_WINDOWS:
            hash_dir = APP_HASH[0:32]
            extract_dir = basename(EXTRACT_DIR)
            extract_root = join(EXTRACT_ROOT, extract_dir, hash_dir)
        else:
            extract_root = join(EXTRACT_ROOT, EXTRACT_DIR, APP_HASH)
            extract_root = get_windows_path_with_unc_prefix(extract_root)
    else:
        extract_root = tempfile.mkdtemp("", "Bazel.runfiles_")
    extract_zip(dirname(__file__), extract_root)
    # IMPORTANT: Later code does `rm -fr` on dirname(runfiles_root) -- it's
    # important that deletion code be in sync with this directory structure
    return join(extract_root, "runfiles")


def execute_file(
    python_program,
    main_filename,
    args,
    env,
    runfiles_root,
    workspace,
):
    # type: (str, str, list[str], dict[str, str], str, str|None, str|None) -> ...
    """Executes the given Python file using the various environment settings.

    This will not return, and acts much like os.execv, except is much
    more restricted, and handles Bazel-related edge cases.

    Args:
      python_program: (str) Path to the Python binary to use for execution
      main_filename: (str) The Python file to execute
      args: (list[str]) Additional args to pass to the Python file
      env: (dict[str, str]) A dict of environment variables to set for the execution
      runfiles_root: (str) Path to the runfiles tree directory
      workspace: (str|None) Name of the workspace to execute in. This is expected to be a
          directory under the runfiles tree.
    """
    # We want to use os.execv instead of subprocess.call, which causes
    # problems with signal passing (making it difficult to kill
    # Bazel). However, these conditions force us to run via
    # subprocess.call instead:
    #
    # - On Windows, os.execv doesn't handle arguments with spaces
    #   correctly, and it actually starts a subprocess just like
    #   subprocess.call.
    # - When running in a zip file, we need to clean up the
    #   workspace after the process finishes so control must return here.
    try:
        subprocess_argv = [python_program]
        if not EXTRACT_ROOT:
            subprocess_argv.append(f"-XRULES_PYTHON_ZIP_DIR={dirname(runfiles_root)}")
        subprocess_argv.append(main_filename)
        subprocess_argv += args
        print_verbose("subprocess env:", mapping=env)
        print_verbose("subprocess cwd:", workspace)
        print_verbose("subprocess argv:", values=subprocess_argv)
        ret_code = subprocess.call(subprocess_argv, env=env, cwd=workspace)
        print_verbose("subprocess exit code:", ret_code)
        sys.exit(ret_code)
    finally:
        if not EXTRACT_ROOT:
            # NOTE: dirname() is called because create_runfiles_root() creates a
            # sub-directory within a temporary directory, and we want to remove the
            # whole temporary directory.
            extract_root = dirname(runfiles_root)
            print_verbose("cleanup: rmtree: ", extract_root)
            shutil.rmtree(extract_root, True)


def finish_venv_setup(runfiles_root):
    python_program = os.path.join(runfiles_root, _PYTHON_BINARY_VENV)
    # When a venv is used, the `bin/python3` symlink may need to be created.
    # This case occurs when "create venv at runtime" or "resolve python at
    # runtime" modes are enabled.
    if not os.path.exists(python_program):
        # The venv bin/python3 interpreter should always be under runfiles, but
        # double check. We don't want to accidentally create symlinks elsewhere
        if not python_program.startswith(runfiles_root):
            raise AssertionError(
                "Program's venv binary not under runfiles: {python_program}"
            )
        symlink_to = find_binary(runfiles_root, _PYTHON_BINARY_ACTUAL)
        os.makedirs(dirname(python_program), exist_ok=True)
        if os.path.lexists(python_program):
            os.remove(python_program)
        try:
            os.symlink(symlink_to, python_program)
        except OSError as e:
            raise Exception(
                f"Unable to create venv python interpreter symlink: {python_program} -> {symlink_to}"
            ) from e
    venv_root = dirname(dirname(python_program))
    pyvenv_cfg = join(venv_root, "pyvenv.cfg")
    if not os.path.exists(pyvenv_cfg):
        print_verbose("finish_venv_setup: create pyvenv.cfg:", pyvenv_cfg)
        python_home = join(runfiles_root, dirname(_PYTHON_BINARY_ACTUAL))
        print_verbose("finish_venv_setup: pyvenv.cfg home:", python_home)
        with open(pyvenv_cfg, "w") as fp:
            # Until Windows supports a build-time generated venv using symlinks
            # to directories, we have to write the full, absolute, path to PYTHONHOME
            # so that support directories (e.g. DLLs, libs) can be found.
            fp.write("home = {}\n".format(python_home))

    return python_program


def main():
    print_verbose("running zip main bootstrap")
    print_verbose("initial argv:", values=sys.argv)
    print_verbose("initial environ:", mapping=os.environ)
    print_verbose("initial sys.executable:", sys.executable)
    print_verbose("initial sys.version:", sys.version)
    print_verbose("stage2_bootstrap:", _STAGE2_BOOTSTRAP)
    print_verbose("python_binary_venv:", _PYTHON_BINARY_VENV)
    print_verbose("python_binary_actual:", _PYTHON_BINARY_ACTUAL)
    print_verbose("workspace_name:", _WORKSPACE_NAME)

    args = sys.argv[1:]

    new_env = {}

    # The main Python source file.
    main_rel_path = _STAGE2_BOOTSTRAP
    if IS_WINDOWS:
        main_rel_path = main_rel_path.replace("/", os.sep)

    runfiles_root = create_runfiles_root()
    print_verbose("extracted runfiles to:", runfiles_root)

    new_env["RUNFILES_DIR"] = runfiles_root

    # Don't prepend a potentially unsafe path to sys.path
    # See: https://docs.python.org/3.11/using/cmdline.html#envvar-PYTHONSAFEPATH
    new_env["PYTHONSAFEPATH"] = "1"

    main_filename = join(runfiles_root, main_rel_path)
    main_filename = get_windows_path_with_unc_prefix(main_filename)
    assert os.path.exists(main_filename), (
        "Cannot exec() %r: file not found." % main_filename
    )
    assert os.access(main_filename, os.R_OK), (
        "Cannot exec() %r: file not readable." % main_filename
    )

    if _PYTHON_BINARY_VENV:
        python_program = finish_venv_setup(runfiles_root)
    else:
        python_program = find_binary(runfiles_root, _PYTHON_BINARY_ACTUAL)
        if python_program is None:
            raise AssertionError(
                "Could not find python binary: " + _PYTHON_BINARY_ACTUAL
            )

    # Some older Python versions on macOS (namely Python 3.7) may unintentionally
    # leave this environment variable set after starting the interpreter, which
    # causes problems with Python subprocesses correctly locating sys.executable,
    # which subsequently causes failure to launch on Python 3.11 and later.
    if "__PYVENV_LAUNCHER__" in os.environ:
        del os.environ["__PYVENV_LAUNCHER__"]

    new_env.update((key, val) for key, val in os.environ.items() if key not in new_env)

    workspace = None
    # If RUN_UNDER_RUNFILES equals 1, it means we need to
    # change directory to the right runfiles directory.
    # (So that the data files are accessible)
    if os.environ.get("RUN_UNDER_RUNFILES") == "1":
        workspace = join(runfiles_root, _WORKSPACE_NAME)

    sys.stdout.flush()
    execute_file(
        python_program,
        main_filename,
        args,
        new_env,
        runfiles_root,
        workspace,
    )


if __name__ == "__main__":
    main()

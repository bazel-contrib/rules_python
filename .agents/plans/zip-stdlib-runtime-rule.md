# Plan: Zipped Standard Library & Executable Runtime Rule

Tracking requirements, past failures and betrayals, edge cases, and design
decisions for packaging hermetic Python standard library files into zip archives
(Issue #1653, PR #4146).

## Requirements

1. **Zipped Standard Library Packaging**:
   - Package pure-Python standard library files into a zip archive for hermetic
     runtimes: `lib/pythonXY.zip` on Unix and `pythonXY.zip` on Windows.
   - Landmark file: Keep unzipped `os.py` on disk so CPython path calculation
     (`getpath.py`/`getpath.c`) locates `sys.prefix` and standard library roots.
   - Flag: Provide `//python/config_settings:zip_stdlib` ('yes'/'no', default
     'yes') allowing users to opt out when on-disk loose files are required.

2. **Binary Rule Wrapping Runtime (`current_interpreter_executable`)**:
   - Provide a binary rule wrapping the toolchain runtime into an executable
     target returning `DefaultInfo(executable = ..., runfiles = ...)` with a
     complete `FilesToRunProvider`.
   - Toolchains and `actions_run()` must pass
     `exec_tools.exec_interpreter[DefaultInfo].files_to_run` as `executable`
     to `ctx.actions.run()`, ensuring Bazel constructs runfiles trees and
     manifests.

3. **No PYTHONPATH Modification**:
   - **Strict Requirement**: Do NOT set or export `PYTHONPATH` in launcher
     wrappers or bootstrap scripts.
   - Python must discover `pythonXY.zip` through standard CPython initialization
     and path derivation mechanisms (`PYTHONHOME` or directory structure).
   - Setting `PYTHONPATH` pollutes child processes and obscures path resolution
     behavior.

4. **No Unnecessary Dependencies**:
   - Avoid unnecessary `@bazel_tools//tools/bash/runfiles` runtime dependencies
     in `py_exec_tools_toolchain`.

5. **Cross-Platform Compatibility**:
   - Fully support Linux, macOS, and Windows.
   - On Windows, provide a `.bat` launcher. Note that
     `--windows_enable_symlinks` is strictly required; running without it is
     unsupported.
   - In `py_console_script_gen`, ensure `_tool` runfiles are staged by passing
     `executable = ctx.attr._tool[DefaultInfo].files_to_run`.

6. **Remote Build Execution (RBE) Hermeticity**:
   - RBE environments execute actions without symlink preservation guarantees
     (bazelbuild/bazel#23620). All runtime files must be staged via proper
     runfiles.

## What Hasn't Worked (Past Betrayals)

1. **Bare File Executable in `actions_run()`**:
   - *Attempt*: Passing `exec_runtime.interpreter` (a bare `File`) directly to
     `ctx.actions.run(executable = action_exe)`.
   - *Betrayal*: While Bazel can in certain cases look up runfiles information
     for a bare `File`, this is finicky behavior that should not be relied
     upon. In practice, relying on it failed to reliably stage or pass runfiles
     across platforms (such as RBE and Windows), leaving `pythonXY.zip` isolated
     in `bazel-out/` and triggering
     `ModuleNotFoundError: No module named 'encodings'`.

2. **Symlinking Interpreter in Place (`ctx.actions.symlink`)**:
   - *Attempt*: Symlinking the toolchain interpreter to declare an executable.
   - *Betrayal*: `ctx.actions.symlink(target_file=...)` does not materialize as
     a symlink on RBE and fails on Windows without elevated privileges.

3. **Setting `PYTHONPATH` in Wrapper Scripts**:
   - *Attempt*: Prepending `TARGET_ZIP` to `PYTHONPATH` in launcher templates.
   - *Betrayal*: Violates the requirement not to mutate `PYTHONPATH`. Mutating
     `PYTHONPATH` breaks downstream subprocesses and masks underlying landmark
     and prefix discovery failures.

4. **`py_console_script_gen` Using `ctx.executable._tool`**:
   - *Attempt*: `ctx.actions.run(executable = ctx.executable._tool)`.
   - *Betrayal*: On Windows, `ctx.executable._tool` is a bare `File` rather
     than `FilesToRunProvider`, preventing runfiles from being staged for
     `py_console_script_gen_py.exe`.

5. **Sourcing External `runfiles.bash` in Bash Launcher**:
   - *Attempt*: Sourcing `@bazel_tools//tools/bash/runfiles/runfiles.bash` and
     relying on `rlocation`.
   - *Betrayal*: Adding `@bazel_tools//tools/bash/runfiles` introduces an
     unnecessary dependency into the toolchain. Omitting that runfiles dep while
     leaving `source .../runfiles.bash` causes
     `ERROR: cannot find bazel_tools/tools/bash/runfiles/runfiles.bash`.
   - *Resolution*: Implement self-contained runfiles resolution directly in
     `interpreter_tmpl.sh` (checking `RUNFILES_MANIFEST_FILE`, `RUNFILES_DIR`,
     `$0.runfiles_manifest`, and `$0.runfiles`) without sourcing external
     runfiles libraries.

## Edge Cases

1. **Windows Symlinks Requirement (`--windows_enable_symlinks`)**:
   - The project strictly requires `--windows_enable_symlinks` to be enabled;
     running without it is unsupported. Manifest-only fallback mode does not
     need special accommodation.

2. **CPython Landmark & Standard Library Zip Discovery**:
   - CPython checks `<sys.prefix>/lib/python<version>.zip` on Unix and
     `<sys.prefix>/python<version>.zip` on Windows.
   - If `PYTHONHOME` is set to the interpreter root in runfiles, CPython
     resolves `sys.prefix` to that directory and automatically finds the zip
     archive without needing `PYTHONPATH`.

3. **Subprocess Isolation**:
   - Wrapper scripts must not export variables that disrupt child Python
     invocations. If `PYTHONHOME` is set, verify whether child processes inherit
     it or if it should only be set when not already defined.

4. **Batch Script Argument Forwarding on Windows**:
   - Windows batch scripts must safely forward `%*` and return `!ERRORLEVEL!`.

## Action Items

1. Create and maintain this plan file in `.agents/plans/`.
2. Update `interpreter_tmpl.sh` and `interpreter_tmpl.bat`:
   - Remove logic setting `PYTHONPATH`.
   - Keep `PYTHONHOME` resolution pointing to the runtime root so CPython finds
     `lib/pythonXY.zip` (Unix) or `pythonXY.zip` (Windows) naturally.
3. Update `py_exec_tools_toolchain.bzl`:
   - Remove `_bash_runfiles` attribute and runfiles merge logic.
4. Run tests and verify stdlib loads without `PYTHONPATH`:
   - `bazel test --config=fast-tests //tests/zip_stdlib/...`
     `//tests/py_exec_tools_toolchain/...`

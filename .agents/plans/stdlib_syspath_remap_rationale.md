# Rationale & Plan: Stdlib sys.path Runfiles Remapping and Toolchain Filtering

## Problem Background

When CPython starts up, its initial bootstrap logic resolves interpreter
symlinks (such as `python3` pointing to extracted repository cache or execution
root locations). This leaks non-runfiles repository directories into `sys.path`,
`sys.base_prefix`, and `sys.prefix` instead of keeping them isolated within the
`.runfiles` tree.

To restore runfiles isolation and support mixing generated and non-generated
runtime files, `_fixup_stdlib_paths()` in
`python/private/site_init_template.py` remaps matching non-runfiles `sys`
prefixes, `sys.path` entries, and `site.PREFIXES` to the runtime root inside
runfiles.

## System Python and `runtime_env_toolchain` Nuance

A naive unconditional remapping of all non-runfiles prefixes breaks system and
platform Python toolchains (such as `runtime_env_toolchain` and Gazelle
WORKSPACE tests).

### Why `_INTERPRETER_ACTUAL_PATH` Is Relative (Not Absolute)

In `python/private/runtime_env_toolchain.bzl`, the toolchain is declared using
an in-build shell script target:
```starlark
py_runtime(
    name = "_runtime_env_py3_runtime",
    interpreter = "//python/private:runtime_env_toolchain_interpreter.sh",
    ...
)
```

Because `runtime.interpreter` is a `File` label rather than an absolute
`interpreter_path` string:
1. `_create_venv()` in `python/private/py_executable.bzl` computes
   `interpreter_actual_path = runfiles_root_path(ctx, runtime.interpreter.short_path)`,
   yielding a **runfiles-relative path**
   (`rules_python/python/private/runtime_env_toolchain_interpreter.sh`).
2. In `site_init_template.py`, `_INTERPRETER_ACTUAL_PATH` is therefore relative,
   so `os.path.isabs(_INTERPRETER_ACTUAL_PATH)` evaluates to `False` and does
   not trigger the early-exit check.
3. At runtime, `runtime_env_toolchain_interpreter.sh` searches `PATH` and
   delegates execution to the host system Python (e.g. `/usr/bin/python3`).
4. CPython initializes with `sys.base_prefix = "/usr"`.
5. Because `/usr` is outside runfiles (`_in_runfiles("/usr") == False`), an
   unfiltered remapper assumes `/usr` is a leaked hermetic runtime directory
   and remaps it to `<runfiles>/rules_python/python/private`.
6. Since system Python does not stage its standard library into runfiles, all
   stdlib imports fail (`ModuleNotFoundError: No module named 'contextlib'`,
   `ModuleNotFoundError: No module named 'pkgutil'`).

## Proposed Solution: Build-Time Signal via Starlark

The determination of whether the runtime's standard library is staged into
runfiles (hermetic runtime) versus living on the host system (system /
environment runtime) is known statically at build/analysis time in Starlark:

1. **In `python/private/py_executable.bzl` (`_create_venv`)**:
   * Inspect the selected runtime from `runtime_details`.
   * For **hermetic toolchains** (where standard library files are staged in
     runfiles), pass `%interpreter_actual_path%` as the runfiles-relative path.
   * For **system / environment toolchains** (e.g. `runtime_env_toolchain` or
     runtimes using `interpreter_path`), pass `%interpreter_actual_path%` as `""`
     (or an absolute path).

2. **In `python/private/site_init_template.py` (`_fixup_stdlib_paths`)**:
   * If `_INTERPRETER_ACTUAL_PATH` is empty or absolute, return immediately on
     line 1 (0 stats, 0 filesystem calls).
   * For hermetic toolchains, perform direct string remapping of non-runfiles
     prefixes (`sys.base_prefix`, `sys.base_exec_prefix`, stdlib `sys.path`
     entries, and `site.PREFIXES`) to the runfiles runtime root.
   * Zero filesystem `stat`, `readlink`, or loop overhead during Python startup.

## Discarded Alternatives

### 1. Runtime Symlink Chain Traversal (`_get_symlink_roots`)

Traversing the interpreter's symlink chain dynamically at runtime via
`os.readlink()` and `os.path.realpath()` to collect valid candidate runtime
roots.

**Why this was discarded**:
* **Complicated**: Adds complex path traversal and cycle-detection logic to the
  critical startup path of every Python binary.
* **Expensive**: Requires multiple `os.stat()`, `os.readlink()`, and
  `os.path.realpath()` syscalls in a loop during site initialization.
* **Conceptually Flawed**: Following symlinks is the very reason why incorrect
  paths ended up in `sys.path` and `sys.base_prefix` in the first place; adding
  more symlink resolution at runtime compounds the issue rather than fixing it
  at the source.

### 2. Checking for "Special" Bazel Path Markers (`/external/`, `/cache/`, `/execroot/`)

Filtering candidate prefixes by checking for Bazel path substrings:
```python
if not any(
    marker in norm_prefix for marker in ("/external/", "/cache/", "/execroot/")
):
    continue
```

**Why this was discarded**:
* **Internal Leaks**: Substrings like `/external/`, `/cache/`, and `/execroot/`
  are internal Bazel details that rules_python shouldn't hardcode or rely on.
* **Environment Specificity**: Paths like `/external/` and `/execroot/` are
  specific to Bazel's execution sandbox and are not applicable at arbitrary
  runtime (e.g. when executing binaries outside the sandbox or across different
  deployment environments).
* **Brittle Heuristics**: Introduces brittle string pattern matching instead of
  relying on concrete build-time or architectural declarations.

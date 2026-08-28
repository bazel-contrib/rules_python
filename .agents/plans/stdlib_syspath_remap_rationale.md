# Implementation Plan & Rationale: Stdlib sys.path Runfiles Remapping

## Problem Background

When Python launches within a Bazel runfiles virtual environment (`.venv`),
CPython follows symlinks when calculating its standard library prefix and
default `sys.path` entries. Because files in `.runfiles/...` are symlinks
pointing into the external repository cache or execution root (e.g.
`.../cache/repos/v1/...` or `execroot/_main/external/+python+...`), CPython
populates `sys.path`, `sys.base_prefix`, and `sys.prefix` with those
underlying repository locations rather than preserving paths within the runfiles
tree.

This leaks underlying repository cache paths into runtime environments and
prevents using a mixture of generated and non-generated files as part of the
Python runtime.

### Why Runfiles Cannot Be Real Files in Bazel

In Bazel (on Linux and macOS), the `.runfiles/` directory is constructed by
Bazel's core runfiles tree builder (`RunfilesTreeUpdater`). To save disk space
and build time, Bazel always populates `.runfiles/` with symlinks pointing to
the underlying artifacts in `bazel-out/` or external repository caches.

There is no Bazel flag or Starlark rule API to force a `.runfiles/` tree to
contain physical file copies instead of symlinks. Even if a Starlark rule
copies files into `bazel-out/` during a build action, Bazel will still create
symlinks to those outputs when assembling the `.runfiles/` tree. The only
situations where files are not runfiles symlinks are when packaging as a
standalone executable archive (`build_python_zip = True`) or on Windows when
symlink support is disabled.

Because POSIX runfiles are inherently symlinks, CPython's startup path
calculation will always resolve them to their real paths on disk. Therefore,
remapping the standard library entries during site initialization
(`_bazel_site_init.py` via `site_init_template.py`) is necessary to restore the
runfiles paths in `sys.path`.

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

## Proposed Solution: Target-Existence-Based Remapping

Instead of guessing whether a toolchain is hermetic or analyzing directory
heuristics, we directly verify ground truth at the target location:
**"Does this stdlib path actually exist at the candidate runfiles location?"**

### Mechanism

1. Determine `runtime_root` from `_INTERPRETER_ACTUAL_PATH` in runfiles.
2. Identify candidate non-runfiles prefixes:
   * In a virtual environment (`sys.prefix != sys.base_prefix`):
     `("base_prefix", "base_exec_prefix")`.
   * Outside a virtual environment:
     `("base_prefix", "base_exec_prefix", "prefix", "exec_prefix")`.
3. For each path in `sys.path`:
   * If the path starts with one of the candidate `old_prefix` roots, compute
     the candidate runfiles target path:
     `cand = target_root + p[len(old_prefix):]`
   * Check if `os.path.exists(cand)`.
   * **If it exists**: replace `sys.path[i] = cand` and record that this prefix
     was remapped.
   * **If it does not exist**: leave `sys.path[i]` untouched.
4. If any paths under `old_prefix` were remapped to runfiles:
   * Update `sys.<attr> = target_root`.
   * Update matching non-runfiles entries in `site.PREFIXES`.

### Why This Works Cleanly

* **Hermetic Toolchains**: The candidate runfiles paths
  (`<runfiles>/+python+.../lib/python3.11`, etc.) physically exist in runfiles,
  so `os.path.exists(cand)` evaluates to `True`, successfully restoring the
  runfiles paths.
* **System / `runtime_env_toolchain`**: The candidate runfiles path
  (`<runfiles>/rules_python/python/private/lib/python3.10`) does not exist, so
  `os.path.exists(cand)` evaluates to `False`, leaving host `/usr` paths intact.
* **Embedded Stdlib / Custom Interpreters**: If an interpreter embeds its own
  stdlib or doesn't use filesystem directory trees, non-existent runfiles paths
  are naturally ignored.
* **Minimal Performance Overhead**: `os.path.exists()` is called only for the
  2–4 entries in `sys.path` that match `old_prefix` (no recursive traversal, no
  symlink chain walking).

## Proposed Code Changes

### `python/private/site_init_template.py`

```python
def _fixup_stdlib_paths():
    """Remap stdlib paths to runfiles if they exist in the runfiles tree."""
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

    target_root = _get_windows_path_with_unc_prefix(runtime_root)
    if _is_windows():
        target_root = target_root.replace("/", os.sep)

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

    remapped_prefixes = set()
    for i, p in enumerate(sys.path):
        norm_p = _norm_path(p)
        for old_prefix in candidate_prefixes.values():
            norm_old = _norm_path(old_prefix)
            if norm_p == norm_old or norm_p.startswith(norm_old + "/"):
                candidate = target_root + p[len(old_prefix):]
                if os.path.exists(candidate):
                    _print_verbose("remap stdlib sys.path:", p, "->", candidate)
                    sys.path[i] = candidate
                    remapped_prefixes.add(old_prefix)
                break

    if not remapped_prefixes:
        return

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
```

## Verification Plan

### Automated Tests

1. Run the reproduction test target to confirm stdlib is in runfiles:
   ```bash
   bazel test --config=fast-tests //tests/bootstrap_impls:stdlib_symlink_syspath_bootstrap_script_test
   ```
2. Run runtime environment toolchain tests:
   ```bash
   bazel test --config=fast-tests //tests/runtime_env_toolchain/...
   ```
3. Run all bootstrap implementation and venv tests:
   ```bash
   bazel test --config=fast-tests //tests/bootstrap_impls/... //tests/venv_site_packages_libs/...
   ```
4. Run Gazelle WORKSPACE tests:
   ```bash
   bazel test --enable_bzlmod=false //modules_mapping:test_merger //modules_mapping:test_generator
   ```

### Manual Verification

Inspect test logs with `RULES_PYTHON_BOOTSTRAP_VERBOSE=1` to confirm that
`sys.path` standard library entries point to `...runfiles/+python+.../lib/...`
instead of underlying repository cache or execroot locations.

## Alternative Proposals & Discarded Alternatives

### Alternative Proposal: Build-Time `runtime.files` Signal

Pass `%interpreter_actual_path%` from `py_executable.bzl` only when
`runtime.files != None`.

**Trade-offs**:
* Eliminates all runtime `os.path.exists()` calls.
* However, `runtime.files` is an imperfect proxy if a custom or embedded Python
  interpreter provides its own stdlib without setting `files`.

### Discarded: Runtime Symlink Chain Traversal (`_get_symlink_roots`)

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

### Discarded: Checking for "Special" Bazel Path Markers (`/external/`, `/cache/`, `/execroot/`)

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

### Discarded: Suffix-Based Stdlib Path String Matching

Checking if paths end with standard library directory suffixes (e.g.
`/lib/pythonX.Y`, `/Lib`, `/DLLs`).

**Why this was discarded**:
* Incomplete across custom Python distribution layouts or modified runtimes.
* Remapping should operate consistently on the runtime root prefixes derived
  from the toolchain configuration rather than guessing folder names.

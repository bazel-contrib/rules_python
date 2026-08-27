# Rationale: Stdlib sys.path Runfiles Remapping and System Python Filtering

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

## The Solution: Symlink Chain Root Matching

Instead of hardcoding or matching against Bazel-specific directory markers
(e.g. `/external/`, `/cache/`, or `/execroot/`), we follow the interpreter's
actual symlink resolution chain from `abs_interpreter` at runtime and collect all
intermediate and final runtime roots into `symlink_roots`:

```python
def _get_symlink_roots(path_str):
    roots = set()
    curr = path_str
    while True:
        roots.add(_norm_path(_get_runtime_root(curr)))
        roots.add(_norm_path(_get_runtime_root(os.path.realpath(curr))))
        if not os.path.islink(curr):
            break
        try:
            target = os.readlink(curr)
        except OSError:
            break
        if not os.path.isabs(target):
            target = os.path.join(os.path.dirname(curr), target)
        target = os.path.abspath(target)
        if target == curr:
            break
        curr = target
    return roots
```

We only remap an `old_prefix` when `_norm_path(old_prefix) in symlink_roots`.

This guarantees that:
* Hermetic CPython runtimes whose symlinks resolved through repository cache or
  external repository directories are recognized because their runtime roots
  belong to the interpreter's symlink chain.
* Host system Python prefixes (`/usr`, etc.) are never in the symlink chain of
  the wrapper script, so they are cleanly ignored without modifying host paths.
* Zero internal Bazel directory naming conventions are assumed.

# Setting up coverage

As of Bazel 6, the Python toolchains and bootstrap logic supports providing
coverage information using the `coverage` library.

As of `rules_python` version `0.18.1`, builtin coverage support can be enabled
when configuring toolchains.

## Enabling `rules_python` coverage support

Enabling the coverage support bundled with `rules_python` just requires setting an
argument when registering toolchains.

For Bzlmod:

```starlark
python.toolchain(
    "@python3_14_toolchains//:all",
    configure_coverage_tool = True,
)
```

For WORKSPACE configuration:

```starlark
python_register_toolchains(
   register_coverage_tool = True,
)
```

:::{note}
This will implicitly add the version of `coverage` bundled with
`rules_python` to the dependencies of `py_test` rules when `bazel coverage` is
run. If a target already transitively depends on a different version of
`coverage`, then the behavior is undefined -- it is undefined which version comes
first in the import path. If you find yourself in this situation, then you'll
need to manually configure coverage (see below).
:::

::::{note}
The bundled `coverage` wheels cover CPython 3.9 and later, including the
freethreaded variants for 3.13+. A platform specific wheel is used for the
Linux (glibc and musl) and macOS toolchains when one is available for the
toolchain's platform and Python version. Otherwise the pure Python
`py3-none-any` wheel is used, which works everywhere but collects coverage
more slowly because it lacks the C tracer.

Windows is not supported because the coverage wrapper is a shell script; use
manually configured coverage (see below) instead.

`py_runtime` warns when the interpreter that `bazel coverage` selects has no
coverage tool. The warning is emitted during analysis, for the runtime
toolchain resolution selected and only when coverage is being collected, so it
does not fire for the many platforms toolchains are registered for but a
given build never uses.

:::{versionchanged} VERSION_NEXT_FEATURE
The platform specific wheels are also used for the musl, `i386`, `ppc64le`
and `riscv64` Linux toolchains instead of the `py3-none-any` wheel.
:::
::::

## Manually configuring coverage

To manually configure coverage support, you'll need to set the
`py_runtime.coverage_tool` attribute. This attribute is a target that specifies
the coverage entry point file and, optionally, client libraries that are added
to `py_test` targets. Typically, this would be a `filegroup` that looked like:

```starlark
filegroup(
  name = "coverage",
  srcs = ["coverage_main.py"],
  data = ["coverage_lib1.py", ...]
)
```

Using `filegroup` isn't required, nor are including client libraries. The
important behaviors of the target are:

*   It provides a single output file OR it provides an executable output; this
    output is treated as the coverage entry point.
*   If it provides runfiles, then `runfiles.files` are included into `py_test`.
*   It can also be a `py_library` of `coverage.py`, e.g. `@pypi//coverage` from
    your {obj}`pip.parse` hub. Then its `coverage/__main__.py` file is used as
    the coverage entry point.

### Using `coverage` from PyPI

To use the version of `coverage` that is locked in your requirements instead of
the one bundled with `rules_python`, point the toolchain to the `coverage`
package of your hub:

```starlark
python.single_version_platform_override(
    coverage_tool = "@pypi//coverage",
    platform = "x86_64-unknown-linux-gnu",
    python_version = "3.13.2",
)
```

Or set `py_runtime.coverage_tool = "@pypi//coverage"` when defining your own
runtime.

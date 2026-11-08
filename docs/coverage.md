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

:::{note}
The bundled `coverage` wheel set covers CPython 3.9 through 3.14 (with
freethreaded variants for 3.13+), and not every platform within that range.
When the interpreter that `bazel coverage` actually selects has no bundled
wheel, `configure_coverage_tool = True` produces no coverage tool and
`bazel coverage` emits empty lcov data; manually configure coverage (see
below) instead.

`py_runtime` warns when this happens. The warning is emitted during analysis,
for the runtime toolchain resolution selected and only when coverage is being
collected, so it does not fire for the many platforms toolchains are
registered for but a given build never uses.
:::

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
*   Otherwise, if one of its output files is `coverage/__main__.py`, then that
    file is treated as the coverage entry point. This allows using the files
    of an extracted `coverage` wheel.

(coverage-from-pypi)=
### Using `coverage` from PyPI

To use the version of `coverage` that is locked in your requirements instead of
the one bundled with `rules_python`, point the toolchain to the extracted files
of the `coverage` package in your {obj}`pip.parse` hub:

```starlark
python.single_version_override(
    coverage_tool = "@pypi//coverage:extracted_whl_files",
    python_version = "3.13.2",
)
```

In `WORKSPACE`, pass the same `coverage_tool` to
{obj}`python_register_toolchains`. Use
{obj}`python.single_version_platform_override` to set it for a single platform
only, or set {attr}`py_runtime.coverage_tool` to
`@pypi//coverage:extracted_whl_files` when defining your own runtime.

:::{note}
Use the `extracted_whl_files` target and not `@pypi//coverage`: the
`py_library` depends on the Python toolchain itself, so using it as the
coverage tool of the toolchain creates a dependency cycle.
:::

# Setting up coverage

As of Bazel 6, the Python toolchains and bootstrap logic supports providing
coverage information using the `coverage` library.

As of `rules_python` version `0.18.1`, builtin coverage support can be enabled
when configuring toolchains.

## Enabling `rules_python` coverage support

Enabling the coverage support provided by `rules_python` just requires setting
an argument when registering toolchains.

For Bzlmod:

```starlark
python.toolchain(
    configure_coverage_tool = True,
    python_version = "3.14",
)
```

This uses the `coverage` package from the `@rules_python_coverage` pip hub,
which `rules_python` defines from its own `uv.lock` file. The lock file has the
latest `coverage` version that supports each of the Python versions starting
from 3.9 and the wheels for all of the platforms configured with
{obj}`pip.default`, so the coverage tool works when cross-building too.

For WORKSPACE configuration:

```starlark
python_register_toolchains(
   register_coverage_tool = True,
)
```

:::{note}
This will implicitly add the version of `coverage` provided by
`rules_python` to the dependencies of `py_test` rules when `bazel coverage` is
run. If a target already transitively depends on a different version of
`coverage`, then the behavior is undefined -- it is undefined which version comes
first in the import path. If you find yourself in this situation, then you'll
need to manually configure coverage (see below).
:::

:::{note}
For WORKSPACE, the bundled `coverage` wheel set covers CPython 3.9 through
3.14 (with freethreaded variants for 3.13+), and not every platform within
that range. When the interpreter that `bazel coverage` actually selects has no
bundled wheel, `register_coverage_tool = True` produces no coverage tool and
`bazel coverage` emits empty lcov data; manually configure coverage (see below)
instead.

`py_runtime` warns when this happens. The warning is emitted during analysis,
for the runtime toolchain resolution selected and only when coverage is being
collected, so it does not fire for the many platforms toolchains are
registered for but a given build never uses.
:::

## Manually configuring coverage

To manually configure coverage support, you'll need to set the
{attr}`py_runtime.coverage_tool` attribute. The preferred way is to pass a
`py_library` of the `coverage` package, e.g. `@pypi//coverage` from your
{obj}`pip.parse` hub. See {ref}`coverage-from-pypi`.

The important behaviors of the target are:

*   It provides {obj}`PyInfo` (e.g. it is a `py_library`), in which case its
    import paths are used to import the `coverage` package. This is the
    preferred way.
*   Otherwise, it provides a single output file OR it provides an executable
    output; this output is treated as the coverage entry point.
*   If it provides runfiles, then `runfiles.files` are included into `py_test`.

:::{deprecated} VERSION_NEXT_FEATURE
Using a target that does not provide {obj}`PyInfo`, e.g. a `filegroup` with
the coverage entry point file, will be deprecated in the next version. Use a
`py_library` instead.
:::

(coverage-from-pypi)=
### Using `coverage` from PyPI

To use the version of `coverage` that is locked in your requirements instead of
the one provided by `rules_python`, point the toolchain to the `coverage`
package in your {obj}`pip.parse` hub:

```starlark
python.single_version_platform_override(
    coverage_tool = "@pypi//coverage",
    platform = "x86_64-unknown-linux-gnu",
    python_version = "3.13.2",
)
```

Or set {attr}`py_runtime.coverage_tool` to `@pypi//coverage` when defining
your own runtime.

:::{note}
The `py_library` itself depends on the Python toolchain. To avoid a dependency
cycle, the coverage tool is built in a configuration where the toolchain has
no coverage tool, which is similar to how `rules_go` builds `nogo`. This only
works when the runtime is defined with the {obj}`py_runtime` macro, which the
toolchains of `rules_python` use.
:::

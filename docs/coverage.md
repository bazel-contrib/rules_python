:::{default-domain} bzl
:::

# Setting up coverage

As of Bazel 6, the Python toolchains and bootstrap logic supports providing
coverage information using the `coverage` library.

As of `rules_python` version `0.18.1`, builtin coverage support can be enabled
when configuring toolchains.

## Enabling `rules_python` coverage support

Enabling the coverage support bundled with `rules_python` just requires setting an
argument when registering toolchains.

For Bzlmod, use {obj}`python.toolchain`:

```starlark
python.toolchain(
    "@python3_14_toolchains//:all",
    configure_coverage_tool = True,
)
```

For WORKSPACE configuration, use {obj}`python_register_toolchains`:

```starlark
python_register_toolchains(
   register_coverage_tool = True,
)
```

:::{note}
This will implicitly add the version of `coverage` bundled with `rules_python`
to the dependencies of {obj}`py_test` rules when `bazel coverage` is run. If a
target already transitively depends on a different version of `coverage`, then
the behavior is undefined -- it is undefined which version comes first in the
import path. If you find yourself in this situation, then set the
{flag}`--coverage` flag to the same `coverage` (see {ref}`coverage-from-pypi`).
:::

With Bzlmod, the bundled `coverage` is a regular dependency of the
{obj}`py_test` and {obj}`py_binary` targets, like the {flag}`--coverage` flag
target, and it is only fetched when coverage is collected. It comes from a pip
hub that `rules_python` locks with a `uv.lock` file, which has the latest
`coverage` version for each Python version starting from 3.9 and the wheels for
all of the platforms of the toolchains. It is locked per `X.Y` Python version,
so setting `configure_coverage_tool = True` for any `X.Y.Z` toolchain enables it
for all of the toolchains of the same `X.Y` version. The {flag}`--coverage` flag
and the {attr}`py_runtime.coverage_tool` attribute take precedence over it.

:::{note}
With WORKSPACE, the bundled `coverage` wheel set covers CPython 3.9 through 3.14
(with freethreaded variants for 3.13+), and not every platform within that
range. When the interpreter that `bazel coverage` actually selects has no
bundled wheel, `register_coverage_tool = True` produces no coverage tool and
`bazel coverage` emits empty lcov data unless `coverage` is provided via
{flag}`--coverage` (see {ref}`coverage-from-pypi`) or manually configured
(see below).

{obj}`py_runtime` warns when this happens. The warning is emitted during
analysis, for the runtime toolchain resolution selected and only when coverage
is being collected, so it does not fire for the many platforms toolchains are
registered for but a given build never uses.
:::

:::{versionchanged} VERSION_NEXT_FEATURE
With Bzlmod, the bundled `coverage` comes from a `uv.lock` based pip hub and it
is added to the dependencies of the executables instead of being the
{attr}`py_runtime.coverage_tool` of the toolchains.
:::

## Manually configuring coverage

To manually configure coverage support, you'll need to set the
{attr}`py_runtime.coverage_tool` attribute. This attribute is a target that
specifies the coverage entry point file and, optionally, client libraries that
are added to `py_test` targets. Typically, this would be a `filegroup` that
looked like:

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

(coverage-from-pypi)=
## Using `coverage` from PyPI

To use the version of `coverage` that is locked in your requirements instead of
the one bundled with `rules_python`, add it to your requirements and set the
{flag}`--coverage` flag to the `coverage` package in your {obj}`pip.parse` hub:

```
# .bazelrc
coverage --@rules_python//python/config_settings:coverage=@pypi//coverage
```

The Python toolchains don't need to be configured. The target is added to the
dependencies of the `py_test` and `py_binary` targets when coverage is
collected, and it isn't fetched for regular builds.

### Using a `.coveragerc` and plugins

To configure `coverage`, wrap it in a `py_library` together with any plugins and
the `.coveragerc` file, and set the {flag}`--coverage` flag to it:

```starlark
py_library(
    name = "coverage",
    data = [".coveragerc"],
    deps = [
        "@pypi//coverage",
        "@pypi//coverage_conditional_plugin",
    ],
)
```

```
# .bazelrc
coverage --@rules_python//python/config_settings:coverage=//:coverage
```

The `.coveragerc` files in the runfiles of the target are merged in order:
options that are lists (e.g. `omit`, `exclude_also` or `plugins`) are combined
and the other options are overridden. The options that Bazel needs, such as
`relative_files`, `source` and `branch`, are always set by `rules_python`.

### Using a different `coverage` for some tests

The {flag}`--coverage` flag can be set for a single target with the
{attr}`py_test.config_settings` attribute:

```starlark
py_test(
    name = "strict_test",
    srcs = ["strict_test.py"],
    config_settings = {
        "@rules_python//python/config_settings:coverage": (
            "//tools:coverage_strict"
        ),
    },
)
```

:::{note}
This builds the test and its dependencies in a separate configuration.
:::

:::{versionadded} VERSION_NEXT_FEATURE
:::

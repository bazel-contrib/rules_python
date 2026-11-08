:::{default-domain} bzl
:::

# How to build a wheel

This guide explains how to use the `py_wheel` rule to build a wheel
file from a `py_library`.

## Basic usage

The `py_wheel` rule takes any file-providing target as input and put its files
into a wheel. Because `py_library` provides its source files, simple cases can
pass `py_library` directly to `py_wheel`:

```starlark
# BUILD.bazel

py_library(
    name = "my_project_lib",
    srcs = glob(["my_project/**/*.py"]),
    # ...
)

py_wheel(
    name = "my_project_wheel",
    distribution = "my-project",
    version = "0.1.0",
    deps = [":my_project_lib"],
)
```

The above will include the *default outputs* of the `py_library`, which are the
direct `.py` files listed in the py library. It does **not** include transitive
dependencies.

## Including and filtering transitive dependencies


Use the `py_package` rule to include and filter the transitive parts of
a `py_library` target.

The `py_package` rule has a `packages` attribute that takes a list of dotted
Python package names to include. All files and dependencies of those packages
are included.

Here is an example:

```starlark
# BUILD.bazel

py_library(
    name = "my_project_lib",
    srcs = glob(["my_project/**/*.py"]),
    deps = ["@pypi//some_dep"],
)

py_package(
    name = "my_project_package",
    # This will only include files for the "my_package" package; other files
    # will be excluded.
    packages = ["my_project"],
)

py_wheel(
    name = "my_project_wheel",
    distribution = "my-project",
    version = "0.1.0",
    # The `py_wheel` rule takes the `py_package` target in the `deps`
    # attribute.
    deps = [":my_project_package"],
)
```

## Disabling `__init__.py` generation

By default, Bazel automatically creates `__init__.py` files in directories to
make them importable. This can sometimes be undesirable when building wheels
because it interfers with namespace packages or makes directories importable
that shouldn't be importable.

It's highly recommended to disable this behavior by setting a flag in your
`.bazelrc` file:

```
# .bazelrc
build --incompatible_default_to_explicit_init_py=true
```

## Setting wheel filename tags from the Python version

To automatically generate the wheel filename and `Requires-Python` metadata for
the active Python version, use make variable syntax in `abi`, `platform`,
`python_requires`, `python_tag`, and `version`:

```starlark
# BUILD.bazel
load("@rules_python//python:packaging.bzl", "py_wheel")

py_wheel(
    name = "my_project_wheel",
    abi = "$(PY_WHEEL_ABI_TAG)",
    distribution = "my-project",
    python_requires = ">=$(PY_MAJOR_DOT_MINOR)",
    python_tag = "$(PY_WHEEL_PYTHON_TAG)",
    version = "0.1.0",
    deps = [":my_project_lib"],
)
```

When built with CPython 3.12, this produces
`my_project-0.1.0-cp312-cp312-any.whl` and sets `Requires-Python: >=3.12` in the
wheel `METADATA`. With freethreaded CPython 3.13, `$(PY_WHEEL_ABI_TAG)` expands
to `cp313t`.

### Available Python version variables

The Python toolchain provides the following make variables by default:

| Variable | Description | Example |
| :--- | :--- | :--- |
| `$(PY_WHEEL_PYTHON_TAG)` | Wheel Python tag | `cp312` |
| `$(PY_WHEEL_ABI_TAG)` | Wheel ABI tag | `cp312`, `cp313t` |
| `$(PY_WHEEL_IMPLEMENTATION_TAG)` | Wheel implementation prefix | `cp` |
| `$(PY_MAJOR_DOT_MINOR)` | Dotted `major.minor` version | `3.12` |
| `$(PY_MAJOR_MINOR_NODOT)` | Dotless `majorminor` version | `312` |
| `$(PY_MAJOR)` | Major version | `3` |
| `$(PY_MINOR)` | Minor version | `12` |
| `$(PY_ABI_FLAGS)` | Runtime ABI flags (`sys.abiflags`) | `""`, `"t"` |
| `$(PY_IMPLEMENTATION_NAME)` | Implementation name | `cpython` |

See {rule}`py_runtime_pair` for the full list of variables.

### Adding custom make variables

To define custom make variables (for example, to compute the package version or
platform tag in Starlark), write a rule that returns
`platform_common.TemplateVariableInfo` and pass it in the `toolchains` attribute
of {obj}`py_wheel`:

```starlark
# wheel_vars.bzl
def _wheel_vars_impl(ctx):
    return [platform_common.TemplateVariableInfo({
        "MY_VERSION": "1.2.3",
    })]

wheel_vars = rule(
    implementation = _wheel_vars_impl,
)
```

```starlark
# BUILD.bazel
load("@rules_python//python:packaging.bzl", "py_wheel")
load(":wheel_vars.bzl", "wheel_vars")

wheel_vars(
    name = "vars",
)

py_wheel(
    name = "my_project_wheel",
    abi = "$(PY_WHEEL_ABI_TAG)",
    distribution = "my-project",
    python_tag = "$(PY_WHEEL_PYTHON_TAG)",
    toolchains = [":vars"],
    version = "$(MY_VERSION)",
    deps = [":my_project_lib"],
)
```

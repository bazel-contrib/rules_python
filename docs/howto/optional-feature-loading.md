:::{default-domain} bzl
:::

# How to optionally load symbols using `features.loadable_symbols`

When writing Bazel rules, macros, or repository extensions that support
multiple versions of `rules_python`, you may want to detect whether a public
symbol (such as {obj}`py_extension` in `//python/cc:py_extension.bzl`) is
available before attempting to load or use it.

Because Starlark `load()` statements are evaluated at parse time and must be at
the top level of a `.bzl` file, unconditionally loading a symbol that does not
exist in older versions of `rules_python` will cause a build error.

The {bzl:obj}`features.loadable_symbols` dictionary in `//python:features.bzl`
allows you to programmatically inspect which symbols are exported by `.bzl`
files in the current `rules_python` version.

## The `features.loadable_symbols` structure

{bzl:obj}`features.loadable_symbols` is a `dict[str, list[str]]` mapping label
strings of `.bzl` files to the list of public symbols they export:

```starlark
load("@rules_python//python:features.bzl", "features")

# Example structure of features.loadable_symbols:
# {
#     "//python/cc:py_extension.bzl": [
#         "py_extension",
#     ],
#     "//python:py_info.bzl": [
#         "PyInfo",
#     ],
# }
```

## Using load() with optional symbols

In repository rules or Bazel module extensions (`repository_ctx` or
`module_ctx`), you generate `.bzl` files dynamically. You can inspect
`features.loadable_symbols` to determine which `load()` statements to write into
a generated compatibility repository.

Re-export the symbol under its standard name if available, or set it to `None`
if it is absent. By generating compatibility files and empty `BUILD.bazel`
files at the exact same relative package paths as `rules_python`, the only
difference in downstream `load()` statements is the repository name:

```starlark
load("@rules_python//python:features.bzl", "features")

def _rules_python_compat_impl(rctx):
    for bzl, symbol_list in rctx.attr.symbols.items():
        loadable = features.loadable_symbols.get(bzl, [])
        lines = []
        for symbol in symbol_list:
            if symbol in loadable:
                lines.append(
                    'load("{}", _{} = "{}")'.format(bzl, symbol, symbol),
                )
                lines.append("{} = _{}".format(symbol, symbol))
            else:
                lines.append("{} = None".format(symbol))

        package, _, filename = bzl.lstrip("/").partition(":")
        path = package + "/" + filename if package else filename
        build_path = package + "/BUILD.bazel" if package else "BUILD.bazel"

        rctx.file(path, content = "\n".join(lines) + "\n")
        rctx.file(build_path, content = "")

rules_python_compat = repository_rule(
    implementation = _rules_python_compat_impl,
    attrs = {
        "symbols": attr.string_list_dict(
            mandatory = True,
            doc = "Map of bzl paths to lists of symbols to optionally load",
        ),
    },
)
```

Instantiate the repository rule by providing a mapping of `.bzl` paths to their
symbols of interest:

```starlark
rules_python_compat(
    name = "rules_python_compat",
    symbols = {
        "//python/cc:py_extension.bzl": ["py_extension"],
    },
)
```

### Using the generated compatibility files

Your macros and rules can load from `@rules_python_compat` using the same
file path as `@rules_python`, testing whether the symbol is `None` before
using it:

```starlark
load("@rules_python_compat//python/cc:py_extension.bzl", "py_extension")

def my_macro(name, **kwargs):
    if py_extension != None:
        py_extension(
            name = name + "_ext",
            **kwargs
        )
    else:
        # Fall back to default behavior for older rules_python versions
        pass
```

## Handling optional targets

In addition to symbol loading, you may need to check whether a specific Bazel
target exists in `rules_python` before referencing its label in dependencies,
toolchains, or attribute defaults.

The {bzl:obj}`features.targets` dictionary in `//python:features.bzl` is a
`dict[str, bool]` mapping public API target labels to `True` when available.

In a macro:

```starlark
load("@rules_python//python:features.bzl", "features")

def my_cc_extension_macro(name, deps = [], **kwargs):
    if features.targets.get("//python/cc:current_py_cc_headers_abi3"):
        deps = deps + ["@rules_python//python/cc:current_py_cc_headers_abi3"]

    # ... define target with deps
```

In a `BUILD` file:

```starlark
load("@rules_python//python:features.bzl", "features")
load("@rules_python//python:py_library.bzl", "py_library")

py_library(
    name = "my_lib",
    srcs = ["my_lib.py"],
    deps = [
        "//my/app:base_lib",
    ] + (
        ["@rules_python//python/cc:current_py_cc_headers_abi3"]
        if features.targets.get("//python/cc:current_py_cc_headers_abi3")
        else []
    ),
)
```

## Checking versions with `features.version`

When a behavioral change or capability is not directly reflected by a public
target or loadable symbol, you can inspect {bzl:obj}`features.version` in
`//python:features.bzl`.

{bzl:obj}`features.version` returns a semver-formatted version string (such as
`"1.0.0"`, `"0.38.0"`, or `""` for unreleased development builds). Avoid
lexicographical string comparisons; instead, split on dots, convert each
component to an integer, and compare them as tuples:

```starlark
load("@rules_python//python:features.bzl", "features")

def _to_tuple(v):
    return tuple([int(x) for x in v.split("-")[0].split(".")])

def check_supports_feature():
    # If version is empty, it is an unreleased build from main which includes
    # all features.
    if not features.version:
        return True
    return _to_tuple(features.version) >= _to_tuple("0.38.0")
```

# Implementation Plan: Canonical Automatic PyPI Proxy Hub

This document defines the locked, production-ready architectural and testing
specifications for implementing dynamic PyPI dependency resolution in
`rules_python`.

## 1. Architectural Strategy: The Canonical `@pypi` Proxy

The `pip` bzlmod extension will automatically synthesize a canonical `@pypi`
proxy repository rule that orchestrates routing to underlying concrete hubs.

### Automatic Proxy Construction & Collision Logic

During the evaluation of the `pip` extension across the dependency graph:
1.  **Unconditional Creation**: The extension will **always** synthesize a
    proxy repository rule with the apparent name `pypi`, even if zero
    `pip.parse` concrete hubs are defined in the dependency graph (in which
    case the proxy is completely valid but empty).
2.  **Collision Prevention**: If a user explicitly defines a concrete hub
    named `pypi` (`pip.parse(hub_name = "pypi")`), the automatic proxy
    synthesis is skipped so the user maintains absolute control over that
    repository name.

In `MODULE.bazel`:
```starlark
pip = use_extension("@rules_python//python/extensions:pip.bzl", "pip")

# Concrete hubs defined for different execution contexts
pip.parse(hub_name = "pypi_a", ...)
pip.parse(hub_name = "pypi_b", ...)
use_repo(pip, "pypi_a", "pypi_b")

# The canonical proxy is automatically created unconditionally:
use_repo(pip, "pypi")
```

### Unified Pypi Hub

The canonical `@pypi` proxy repository matches exactly how concrete hubs create
their directory structure: a root package for shared configuration settings, and
a dedicated subdirectory (subpackage) for each PyPI package.

Here is a complete, representative code example of what the generated files in
`@pypi` will look like when resolving packages between `pypi_a` and `pypi_b`:

#### 1. `@pypi//BUILD.bazel` (Root Package)
The root package contains the shared `config_setting` targets following the
`_is_pypi_hub_<name>` private naming convention. Leading underscores are strictly
applied because these configuration settings are an internal implementation
detail of the proxy repository and are not intended to be a public API.

```starlark
package(default_visibility = ["//visibility:public"])

config_setting(
    name = "_is_pypi_hub_pypi_a",
    flag_values = {
        "@rules_python//python/config_settings:pypi_hub": "pypi_a",
    },
)

config_setting(
    name = "_is_pypi_hub_pypi_b",
    flag_values = {
        "@rules_python//python/config_settings:pypi_hub": "pypi_b",
    },
)
```

#### 2. `@pypi//foo/BUILD.bazel` (PyPI Package Subpackage)
Each PyPI package subpackage defines exactly the same standard aliases (`pkg`,
`whl`, `data`, `dist_info`, `extracted_wheel_files`), resolving dynamically to
the concrete hub based on the root private configuration settings:

```starlark
package(default_visibility = ["//visibility:public"])

alias(
    name = "foo",
    actual = ":pkg",
)

alias(
    name = "pkg",
    actual = select({
        "//:_is_pypi_hub_pypi_a": "@pypi_a//foo:pkg",
        "//:_is_pypi_hub_pypi_b": "@pypi_b//foo:pkg",
        # When pypi_hub is "auto" (unset), it defaults to the first defined
        # concrete hub (or designated fallback via pip.default).
        "//conditions:default": "@pypi_a//foo:pkg",
    }),
)

alias(
    name = "whl",
    actual = select({
        "//:_is_pypi_hub_pypi_a": "@pypi_a//foo:whl",
        "//:_is_pypi_hub_pypi_b": "@pypi_b//foo:whl",
        "//conditions:default": "@pypi_a//foo:whl",
    }),
)

alias(
    name = "data",
    actual = select({
        "//:_is_pypi_hub_pypi_a": "@pypi_a//foo:data",
        "//:_is_pypi_hub_pypi_b": "@pypi_b//foo:data",
        "//conditions:default": "@pypi_a//foo:data",
    }),
)

alias(
    name = "dist_info",
    actual = select({
        "//:_is_pypi_hub_pypi_a": "@pypi_a//foo:dist_info",
        "//:_is_pypi_hub_pypi_b": "@pypi_b//foo:dist_info",
        "//conditions:default": "@pypi_a//foo:dist_info",
    }),
)

alias(
    name = "extracted_wheel_files",
    actual = select({
        "//:_is_pypi_hub_pypi_a": "@pypi_a//foo:extracted_wheel_files",
        "//:_is_pypi_hub_pypi_b": "@pypi_b//foo:extracted_wheel_files",
        "//conditions:default": "@pypi_a//foo:extracted_wheel_files",
    }),
)
```

### Fallback Hub Precedence (`"auto"`)

When a target depends on `@pypi//foo` and the active build setting is `"auto"`,
the proxy resolves to a concrete hub using the following precedence:
1.  **Designated Fallback**: If the user has explicitly designated a fallback
    concrete hub via `pip.default(default_hub = "...")` in their root
    `MODULE.bazel`, the proxy routes to it.
2.  **First Defined Hub**: If no fallback is explicitly designated via
    `pip.default()`, the proxy **automatically routes to the first defined
    concrete hub** parsed during extension evaluation (e.g., `pypi_a`).

```starlark
# Optional: explicitly override the "auto" fallback hub
pip.default(
    default_hub = "pypi_b", 
)
```

## 2. Core Rule Integration: `config_settings` Transitions

Users will switch active hubs using the standard, highly generic
`config_settings` transition attribute on executable targets.

### Build Setting Definition

In `python/config_settings/BUILD.bazel`:

```starlark
string_flag(
    name = "pypi_hub",
    build_setting_default = "auto", # Default value is "auto"
    visibility = ["//visibility:public"],
)
```

In `python/private/common_labels.bzl`:
```starlark
    PYPI_HUB = str(Label("//python/config_settings:pypi_hub")),
```

In `python/private/transition_labels.bzl`:
```starlark
_BASE_TRANSITION_LABELS = [
    # ... existing transition labels ...
    labels.PYPI_HUB,
]
```

Because `py_binary` and `py_test` implement an incoming transition
(`_transition_executable_impl`) that automatically processes any
`config_settings` keys matching `TRANSITION_LABELS`, **this provides complete
transition capabilities with zero changes to our core rule definitions**.

### Usage in BUILD.bazel

Libraries consume packages through the canonical proxy:

```starlark
py_library(
    name = "common",
    deps = ["@pypi//foo"], # Apparent proxy repository
)
```

Binaries change the active hub by transitioning the build setting:

```starlark
# Resolves @pypi -> pypi_a (first defined / designated fallback)
py_binary(
    name = "bin_default",
    deps = [":common"],
)

# Resolves @pypi -> pypi_b via transition
py_binary(
    name = "bin_b",
    deps = [":common"],
    config_settings = {
        "//python/config_settings:pypi_hub": "pypi_b",
    },
)
```

## 3. Integration Testing Specification

We will construct a comprehensive Bazel-in-Bazel integration test suite in
`tests/integration/unified_pypi/` to guarantee correctness and verify
transitions.

The integration test suite will assert:
1.  **`"auto"` Precedence**: Author a test asserting `bazel run //:bin_default`
    correctly inherits `"auto"` and resolves dependencies from the first
    defined concrete hub (or designated fallback).
2.  **Transitional Resolution**: Author a test asserting two binary targets in
    the same package with different `config_settings` successfully resolve
    dependencies and execute against their respective concrete hubs (`pypi_a`
    vs `pypi_b`).
3.  **Command Line Override**: Author a test asserting
    `bazel run --//python/config_settings:pypi_hub=pypi_b //:bin_default`
    successfully forces the executable to run using imports resolved from
    `pypi_b`.

## 4. Execution Steps

1.  **Phase 1**: Define `pypi_hub` `string_flag` and register it in
    `common_labels.bzl` and `transition_labels.bzl`.
2.  **Phase 2**: Update `python/private/pypi/extension.bzl` to synthesize the
    canonical `pypi` proxy repository rule.
3.  **Phase 3**: Implement `proxy_hub_repository` rule (or equivalent generation
    logic) that builds the root `config_setting` package and individual PyPI
    package subpackages.
4.  **Phase 4**: Author the Bazel-in-Bazel integration test suite in
    `tests/integration/unified_pypi/`.
5.  **Phase 5**: Run all tests and verify full pass before PR submission.

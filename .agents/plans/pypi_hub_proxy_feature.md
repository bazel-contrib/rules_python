# Implementation Plan: Canonical Automatic PyPI Proxy Hub

This document defines the locked, production-ready architectural, Starlark API,
and testing specifications for implementing dynamic PyPI dependency resolution in
`rules_python` using the `venv` flag.

---

## 1. Architectural Strategy: The Canonical `@pypi` Proxy

The `pip` bzlmod extension will automatically synthesize a canonical `@pypi`
proxy repository rule that orchestrates routing to underlying concrete hubs.

### Bzlmod-Exclusive Scope

The Unified PyPI Hub Proxy is an **exclusive feature of `bzlmod`**. Legacy
`WORKSPACE` evaluations using independent `pip_parse` repository macros are not
supported, as bzlmod's module extension architecture provides the required
centralized coordination to inspect and interlink cross-module hubs.

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

# Designate 'pypi_b' as the default hub for the unified '@pypi' repository
pip.default(default_hub = "pypi_b")

# The canonical proxy is automatically created unconditionally:
use_repo(pip, "pypi")
```

### Unified PyPI Hub

The canonical `@pypi` proxy repository matches exactly how concrete hubs create
their directory structure: a root package for shared configuration settings, and
a dedicated subdirectory (subpackage) for each PyPI package.

Here is a complete, representative code example of what the generated files in
`@pypi` will look like when resolving packages between `pypi_a` and `pypi_b`:

#### 1. `@pypi//BUILD.bazel` (Root Package)
The root package contains the shared `config_setting` targets following the
`_is_venv_<name>` private naming convention. Leading underscores are strictly
applied because these configuration settings are an internal implementation
detail of the proxy repository and are not intended to be a public API.

```starlark
package(default_visibility = ["//visibility:public"])

config_setting(
    name = "_is_venv_pypi_a",
    flag_values = {
        "@rules_python//python/config_settings:venv": "pypi_a",
    },
)

config_setting(
    name = "_is_venv_pypi_b",
    flag_values = {
        "@rules_python//python/config_settings:venv": "pypi_b",
    },
)
```

#### 2. `@pypi//foo/BUILD.bazel` (PyPI Package Subpackage)
Each PyPI package subpackage defines the standard aliases (`pkg`, `whl`, `data`,
`dist_info`, `extracted_wheel_files`), plus a complete **union of all custom
`extra_hub_aliases`** defined across all concrete hubs. 

Each alias resolves dynamically to the active concrete hub based on the root
private configuration settings:

```starlark
package(default_visibility = ["//visibility:public"])

alias(
    name = "foo",
    actual = ":pkg",
)

alias(
    name = "pkg",
    actual = select({
        "//:_is_venv_pypi_a": "@pypi_a//foo:pkg",
        "//:_is_venv_pypi_b": "@pypi_b//foo:pkg",
        # When venv is "auto" (unset), it defaults to the designated fallback
        # (or first defined concrete hub).
        "//conditions:default": "@pypi_b//foo:pkg",
    }),
)

alias(
    name = "whl",
    actual = select({
        "//:_is_venv_pypi_a": "@pypi_a//foo:whl",
        "//:_is_venv_pypi_b": "@pypi_b//foo:whl",
        "//conditions:default": "@pypi_b//foo:whl",
    }),
)

# ... standard aliases for data, dist_info, extracted_wheel_files ...

# 3. Unionized custom extra alias (defined in pypi_a but missing in pypi_b):
alias(
    name = "my_custom_tool",
    actual = select({
        "//:_is_venv_pypi_a": "@pypi_a//foo:my_custom_tool",
        # Unrepresented branch routes to execution failure target:
        "//:_is_venv_pypi_b": "//:_missing_package_error_pypi_b_foo",
        "//conditions:default": "@pypi_a//foo:my_custom_tool",
    }),
)
```

### Disjoint Hub Packages & Execution-Phase Failure

If a package exists in one concrete hub but is missing in another (e.g., `scipy`
is in `pypi_b` but not `pypi_a`), our proxy synthesizes a package subpackage for
the union of all packages. 

To ensure that `bazel cquery` and `bazel query` successfully analyze over the
entire transitive build graph without failing, unrepresented select branches
must route to a dedicated **execution-phase error rule**.

```starlark
# In @pypi//scipy/BUILD.bazel
alias(
    name = "pkg",
    actual = select({
        # Routes to execution-phase action failure target:
        "//:_is_venv_pypi_a": "//:_missing_package_error_pypi_a_scipy",
        "//:_is_venv_pypi_b": "@pypi_b//scipy:pkg",
        "//conditions:default": "@pypi_b//scipy:pkg",
    }),
)
```

The synthesized `//:_missing_package_error_XX` rule in `@pypi//BUILD.bazel`
returns standard Starlark Python providers so analysis/cquery passes, but
registers a build action that fails when executed:

```
Dependency Error: Third-party package 'scipy' is not available when building under PyPI hub 'pypi_a'.
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
# Explicitly override the "auto" fallback hub
pip.default(
    default_hub = "pypi_b", 
)
```

---

## 2. Core Rule Integration: `config_settings` Transitions

Users will switch active hubs using the standard, highly generic
`config_settings` transition attribute on executable targets.

### Build Setting Definition

In `python/config_settings/BUILD.bazel`:

```starlark
string_flag(
    name = "venv",
    build_setting_default = "auto", # Default value is "auto"
    visibility = ["//visibility:public"],
)
```

In `python/private/common_labels.bzl`:
```starlark
    VENV = str(Label("//python/config_settings:venv")),
```

In `python/private/transition_labels.bzl`:
```starlark
_BASE_TRANSITION_LABELS = [
    # ... existing transition labels ...
    labels.VENV,
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
# Resolves @pypi -> pypi_b (default hub / designated fallback)
py_binary(
    name = "bin_default",
    deps = [":common"],
)

# Resolves @pypi -> pypi_a via transition
py_binary(
    name = "bin_a",
    deps = [":common"],
    config_settings = {
        "//python/config_settings:venv": "pypi_a",
    },
)
```

### Analysis Cache & Memory Best Practices

Because transitions fork the Bazel configuration, building targets with highly
diversified `config_settings` across large build graphs will result in
re-analysis and re-compilation of shared dependencies. 

We will include explicit documentation guidelines advising users to keep their
`venv` transition configurations localized and minimized to preserve Bazel
caching and memory efficiency.

---

## 3. Integration Testing Specification

We will construct a comprehensive Bazel-in-Bazel integration test suite in
`tests/integration/unified_pypi/` to guarantee correctness and verify
transitions.

The integration test suite will assert:
1.  **`"auto"` Precedence**: Author a test asserting `bazel run //:bin_default`
    correctly inherits `"auto"` and resolves dependencies from the designated fallback.
2.  **Transitional Resolution**: Author a test asserting two binary targets in
    the same package with different `config_settings` successfully resolve
    dependencies and execute against their respective concrete hubs (`pypi_a`
    vs `pypi_b`).
3.  **Command Line Override**: Author a test asserting
    `bazel run --//python/config_settings:venv=pypi_a //:bin_default`
    successfully forces the executable to run using imports resolved from
    `pypi_a`.
4.  **Disjoint Execution Failure**: Author a test asserting `bazel cquery` over
    a target depending on an unrepresented missing package succeeds, while
    `bazel run` on that target gracefully fails during execution with the exact
    synthesized error message.
5.  **Unionized Extra Hub Aliases**: Author a test asserting that a binary
    successfully runs using a custom `extra_hub_aliases` target resolved
    through the `@pypi proxy`.

---

## 4. Execution Steps

1.  **Phase 1**: Define `venv` `string_flag` and register it in
    `common_labels.bzl` and `transition_labels.bzl`.
2.  **Phase 2**: Update `python/private/pypi/extension.bzl` to synthesize the
    canonical `pypi` proxy repository rule.
3.  **Phase 3**: Implement `missing_package_error` execution failure rule and
    the `proxy_hub_repository` generation logic.
4.  **Phase 4**: Author the Bazel-in-Bazel integration test suite in
    `tests/integration/unified_pypi/`.
5.  **Phase 5**: Run all tests and verify full pass before PR submission.

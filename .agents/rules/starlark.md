---
trigger: glob
description: Starlark Language, Macro, and Testing Invariants
globs: "*.bzl,BUILD,BUILD.bazel,*.bazel"
---

# Starlark Language & Macro Invariants

## Macro Target Canonicalization
* In macro implementations, internal repository target references **MUST** be
  canonicalized using `str(Label("//path/to:target"))` so they resolve in the
  macro's module context rather than the caller's repository context.
* Note that `python/private/common_labels.bzl` defines `labels`, a struct
  containing common canonicalized label strings used across the project.

## Manual Tag on Internal Macro Helper Targets
* When macros instantiate internal helper targets (such as private rule targets
  for artifact extraction or linking support), always include `tags = ["manual"]`.
* **Why**: This prevents internal helper targets from being implicitly built when
  wildcard target patterns (e.g., `//...`) are expanded.

## Private Alias Pattern when Appending to User `deps`
* When macros append internal helper targets to user-provided dependency lists
  (`deps`), use private alias targets (e.g.
  `//python/private/cc:current_py_cc_headers_private_alias`) to prevent
  "duplicate dependency label" analysis errors if the user also explicitly
  passes the public target label in their `deps` (including in `select()`
  expressions).

## Attribute Normalization at Function Entry
* Always normalize input list attributes at the start of macro definitions
  (e.g., `deps = deps or []`, `copts = copts or []`).
* **Why**: This avoids inlining the normalization as part of a complex
  expression later in the macro expansion.

## Control Flow & Algorithmic Restrictions
* **Iterative Algorithms Only (No Recursion)**: Starlark does not support
  recursive function calls; always implement iterative algorithms using bounded
  loops.
* **Iterable `for` Loops Only (No `while` Loops)**: Starlark does not support
  `while` loops; iterate over fixed-size ranges or explicit collections.

## Depset Element Invariants & Optimizations
* **Providers over Structs for Depset Elements**: Use `provider()` (without
  `-Info` suffix, e.g. `*Fileset`) instead of `struct()` for composite objects
  in depsets; providers perform key sharing and reduce memory overhead.
* **Depset Element Immutability**: All depset elements and nested provider
  fields must be immutable when `depset()` is called (eager check before rule
  freeze). Use `tuple[T]` or `depset[T]` in providers placed into depsets; do
  not use mutable `list[T]`.

## Code Style & Conventions
* **Dict union (`|`)**: Use `|` instead of `dicts.add(...)` from
  `@bazel_skylib//lib:dicts.bzl` when merging dictionaries.
* **Non-Info Provider Naming**: Add `# buildifier: disable=name-conventions`
  above `provider()` declarations that do not end in `Info` (e.g. `*Fileset`).
* **Docstring Formatting Invariants**: Use triple-quoted strings for multi-line
  docstrings without trailing backslashes (`\`) for line continuation.
* **No Bazel Copyright Headers**: Do not add Bazel copyright headers to new or
  existing files unless explicitly directed by the user.
* **Line Length & Wrapping**: Wrap Markdown and Starlark lines to 80 columns in
  accordance with `.editorconfig`.

## Starlark Testing (`rules_testing`)
* **`rules_testing` over `bazel_skylib`**: Always use `@rules_testing` (analysis
  tests with `env.expect.that_...`) rather than `bazel_skylib` for Starlark
  rule analysis tests.
* **Analysis Test Two-Part Structure**: Separate tests into a setup target
  function `def _test_foo(name)` calling `analysis_test` and an implementation
  function `def _test_foo_impl(env, target)`.
* **Test Suite Registration**: Collect test setup functions in a private
  `_tests` list and register them cleanly via `test_suite(name = name, tests =
  _tests)`.

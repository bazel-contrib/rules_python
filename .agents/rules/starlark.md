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
* **Reuse `python/private/common_labels.bzl`**: When a target label is listed in
  `python/private/common_labels.bzl` (or shared across multiple `.bzl` files
  such as `flags.bzl` and `config_settings.bzl`), load `labels` from
  `:common_labels.bzl` and use `labels.<NAME>` (or `Label(labels.<NAME>)`)
  instead of redefining duplicate `Label("//...")` values.

## Manual Tag on Internal Macro Helper Targets
* When macros instantiate internal helper targets (such as private rule targets
  for artifact extraction or linking support), always include
  `tags = ["manual"]`.
* **Why**: This prevents internal helper targets from being implicitly built
  when wildcard target patterns (e.g., `//...`) are expanded.

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

## `executable = True` Attributes
* Use `allow_files = True` (with an explanatory comment), not
  `allow_single_file = True`, when the attribute may accept `py_binary` (whose
  `DefaultInfo.files` has multiple files).

## native.test_suite API
* Don't forward target `tags` to `native.test_suite`; tags on test suites filter
  tests instead of setting target execution behavior.

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
* **Dedicated Providers over Filtering `DefaultInfo.files`**: When a rule needs
  a subset of a dependency's outputs (e.g., binaries without a sibling `.txt`
  manifest), return a dedicated provider (e.g., `_ReleaseFilesInfo`) instead of
  filtering `DefaultInfo.files` by filename or extension.

## Repository Rules & Code Generation
* **Structured Attributes**: Pass separate typed attributes (`attr.string_list`,
  `attr.string_list_dict`) instead of pre-rendered `BUILD` text or JSON blobs;
  render `BUILD.bazel` in the rule implementation.
* **Single-Value Templates**: For generated file templates with one interpolated
  value, use a top-level string and `.format()`.
* **Data Constants in Generated `.bzl` Files**: Use `json.encode_indent()` to
  write JSON-compatible data (`dict`, `list`, `str`, `int` without `bool` or
  `None`) as `.bzl` constants instead of custom formatting helpers.
* **Reuse `http_file`**: Use `http_file` from
  `@bazel_tools//tools/build_defs/repo:http.bzl` for single-file downloads. Omit
  `downloaded_file_path` unless required and reference `@<repo>//file`.
* **`rctx.read()` Files**: Do not add `exports_files()` for files only read via
  `rctx.read(Label(...))`.
* **`repository_ctx.repo_metadata`**: `repository_ctx.repo_metadata` was
  introduced in Bazel 8.3.0.

## BUILD & Target Hygiene
* Do not use deprecated `$(location)` or `$(locations)`. In execution-root
  contexts (such as `genrule.cmd`), use `$(execpath ...)` and
  `$(execpaths ...)`.
* Do not define overlapping `filegroup` targets or `exports_files` globs in the
  same `BUILD` package; reconcile or compose them.
* Move complex loops and branching out of `BUILD` files into `.bzl` macros.
* When exposing data files across packages, define a named `filegroup` in the
  owning package rather than referencing raw source files in caller `data`.

## Code Style & Conventions
* Forward unused wrapper macro arguments via `**kwargs` instead of duplicating
  the underlying rule or macro signature.
* Silence unused Starlark variables with `_ = a, b  # @unused`.
* Prefer analysis-time validation over loading-time checks so defined but
  unbuilt targets do not cause loading-time failures.
* Prefer `ctx.actions.write` over spawning a subprocess for small content known
  at analysis time.
* In `genrule.cmd` or multi-line command strings, place closing triple quotes
  immediately after the last argument (`"""\n... --flag"""`) when trailing
  newlines would break chained commands.
* **Do Not Export `BUILD` Files Unnecessarily**: Do not add `BUILD` or
  `BUILD.bazel` to `exports_files(...)` unless strictly required.
* **No Nested List Comprehensions**: Do not write nested list comprehensions
  (`[x for y in ... for x in ...]`). Use explicit `for` loops instead.
* **Direct Attribute Access**: Use normal attribute access (`x.field`) instead
  of `getattr(x, "field", default)` for fields defined on a provider or struct
  schema. When an object may be one of multiple provider/struct variants with
  different field sets, guard once with `if hasattr(x, "field"):` (with a
  comment explaining why the field may be absent) and use normal attribute
  access inside the block.
* **Dict union (`|`)**: Use `|` instead of `dicts.add(...)` from
  `@bazel_skylib//lib:dicts.bzl` when merging dictionaries.
* **Type Checks (`@bazel_skylib//lib:types.bzl`)**: Prefer `types.is_*` helpers
  (e.g., `types.is_dict(x)`, `types.is_list(x)`, `types.is_string(x)`) from
  `@bazel_skylib//lib:types.bzl` instead of `type(x)` comparisons.
* **Non-Info Provider Naming**: Add `# buildifier: disable=name-conventions`
  above `provider()` declarations that do not end in `Info` (e.g. `*Fileset`).
* **`config_setting` Naming**: Prefix `config_setting` names with `is_` (e.g.
  `is_linux_x86_64`), so that `select()` keys read as conditions.
* **Explicit Required Parameters**: Declare required parameters explicitly
  instead of passing them through `**kwargs`. Document `Args:` and `Returns:`.
* **Docstring Formatting Invariants**: Use triple-quoted strings for multi-line
  docstrings without trailing backslashes (`\`) for line continuation.
* **Concise API Docstrings**: Keep docstrings brief: state purpose and
  arguments, link to shared symbols (`{obj}`) or guides (`{ref}`) instead of
  repeating rules, and put extended examples in `docs/`.
* **Workaround Comments**: Comment non-obvious workarounds with the intent, why
  the direct approach fails, and why the workaround works.
* **No Bazel Copyright Headers**: Do not add Bazel copyright headers to new or
  existing files unless explicitly directed by the user.
* **Line Length & Wrapping**: Wrap Markdown and Starlark lines to 80 columns in
  accordance with `.editorconfig`.
  * **Long string literals**: Do not line-break long string literals (such as
    URLs or hashes) to fit line length limits; allow them to exceed the limit.
  * **Long ternaries**: Use `if`/`else` statements when `a if cond else b`
    exceeds 80 columns (`buildifier` collapses multi-line ternaries).

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
* Use `rules_testing`'s built-in `TestingAspectInfo` and `target.attr()` instead
  of custom aspect providers to inspect rule attributes.
* For single-target `analysis_test`, use singular `target = ...` and top-level
  `config_settings = ...` instead of plural `targets = {"subject": ...}`.
* In multi-target tests, name target variables after their roles rather than
  `subject`.
* Use a single `contains_at_least([...])` or `contains_exactly([...])` call
  instead of chaining multiple `.contains(...)` assertions on the same
  collection.

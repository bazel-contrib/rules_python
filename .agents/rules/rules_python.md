---
trigger: model_decision
description: rules_python-specific Bzlmod, PyPI, and rule usage invariants
---

# `rules_python` Bzlmod & Rule Invariants

## Unified `@pypi` Hub & `pip.dep()` Declarations (`MODULE.bazel`)
* Declare `pip.dep(name = "<pkg>")` on the non-dev `pip` extension in
  `MODULE.bazel` (with `"pypi"` in `use_repo(pip, "pypi", ...)`) for every
  `@pypi//<pkg>` target referenced by non-test rules, macros, or `BUILD` files
  under `python/**` (directly or via `alias`).
* **Why**: `pip.dep()` registers abstract PyPI package targets in the unified
  `@pypi` hub so downstream Bzlmod consumers do not fail during loading or
  analysis when `<pkg>` is absent from their `pip.parse()` lockfiles. Package
  names in `pip.dep(name = "...")` are normalized (hyphens and underscores map
  to the same name).

## Minimum Supported Bazel Version
* `//:version.bzl` defines `MINIMUM_BAZEL_VERSION`. Do not add compatibility
  logic, feature guards, or comments for older Bazel versions.
* When guarding a feature added after `MINIMUM_BAZEL_VERSION`, verify and
  comment the exact Bazel version that introduced it.

## Internal Labels & Helpers
* **Toolchain Type Labels**: Define toolchain type constants in
  `//python/private/toolchain_types:toolchain_types.bzl` and targets in
  `//python/private/toolchain_types:BUILD.bazel`.
* **`render` Helpers (`//python/private:text_util.bzl`)**: Use `render.*`
  (`render.string`, `render.toolchain`, `render.call`, `render.list`) instead of
  `repr()` for Starlark calls; use `json.encode_indent()` for data constants.
* **`@bazel_tools` `bzl_library` Deps**: Use `"//python/private:bazel_tools"` in
  `bzl_library` `deps` for files loading `@bazel_tools//...`.

## WORKSPACE & Bzlmod Parity
* **Extend Existing Rules Over Adding Parallel Rules**: When bringing a Bzlmod
  tag attribute (such as `pip.parse(uv_lock = ...)`) to an existing `WORKSPACE`
  rule or macro (`pip_parse` / `pip_repository`), add the attribute to the
  existing rule and reuse its pipeline (`parse_requirements` ->
  `requirements.bzl.tmpl.workspace` -> `whl_library`) instead of creating a
  separate rule or duplicating Bzlmod's hub/spoke repo graph.
* **Extract Shared Pure Helpers from Bzlmod Extensions**: When `WORKSPACE` code
  needs pure functions or data defined in a Bzlmod extension file (such as
  `default_platforms()` in `extension.bzl`), move them into a standalone
  Bzlmod-agnostic `.bzl` file instead of duplicating definitions.
* **Preserve Vendored `requirements.bzl` Portability in `WORKSPACE`**:
  `pip_repository` outputs (`requirements.bzl`) may be vendored and evaluated
  on any host platform. Only emit direct Bazel downloader attributes (`urls`,
  `integrity`, `filename`) into `requirements.bzl` when a package resolves to
  the same distribution across all target platforms
  (`len({src.url: None for src in whl.srcs}) == 1`); otherwise append
  `--hash=<digest>` flags to the requirement line so `pip` selects the host
  wheel while enforcing lockfile hashes.
* For new `WORKSPACE` macros without an existing rule counterpart, match Bzlmod
  extension defaults, tag schemas (e.g., `configure` list of dicts), and
  single-hub multi-version structure, sharing configuration and hub logic in
  common private `.bzl` helpers.
* When `WORKSPACE` repos depend on downloaded manifests, split setup into a
  manifest repo rule (writes unfiltered `DIST_MANIFESTS` and a bound
  registration macro to `dist_manifest.bzl`) and a registration macro (filters
  platforms, instantiates tool repos, and registers the hub; also accepts
  explicit `urls` without a manifest).

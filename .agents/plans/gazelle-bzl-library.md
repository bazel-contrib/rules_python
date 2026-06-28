# Plan: Gazelle Migration for bzl_library Targets

This plan outlines the strategy, implementation details, edge cases, and
special directions for migrating `rules_python` to use `bazel-skylib`'s Gazelle
integration to automate the generation and maintenance of `bzl_library`
targets.

## 1. Objective

Automate the maintenance of `bzl_library` targets across the repository to
simplify dependency tracking, while minimizing risk and keeping tests and
examples completely pristine.

## 2. Implementation Strategy

*   **Plugin Integration:** Integrate `bazel_skylib_gazelle_plugin` as a
    `dev_dependency` in `MODULE.bazel`.
*   **Gazelle Location:** Place all Gazelle rules and targets (such as the
    `gazelle_binary` and the `gazelle` rule itself) entirely within
    `tools/private/gazelle` to prevent any loading-time or analysis-time
    production dependencies on Gazelle.
*   **Root Configuration:** Root-level configuration is limited to Gazelle
    directives (comments) in the root `BUILD.bazel` to guide the plugin's
    behavior.
*   **Directory Exclusions:**
    *   Exclude `tests/` and `examples/` directories from Gazelle scanning to
        ensure they remain completely untouched and match `upstream/main`.
    *   Exclude top-level dev-setup files (`internal_dev_setup.bzl`,
        `python/private/internal_dev_deps.bzl`) from Gazelle to avoid
        generating targets that would require creating helper targets inside the
        pristine `tests/` directory.
    *   **Bzlmod & Repository-Phase Exclusions:** Exclude Starlark files that
        are only evaluated during the Bzlmod or repository-loading phases (e.g.,
        module extensions, repository rules, or startup setup macros). These
        files do not run at analysis/build time and therefore do not need
        `bzl_library` targets.
        *   Examples: `gazelle/deps.bzl` (repository-phase Go helper) and
            `extensions.bzl` (Bzlmod module extension files, such as those in
            `gazelle/python/` and `gazelle/python/private/`) are excluded.
    *   **Special Case Exclusions:**
        *   `internal_dev_deps.bzl`: Exclude all instances of this file across
            the repository (including in the root, `python/private/`, and
            `gazelle/` directories) from Gazelle processing, as they are
            dev-setup files that should not pollute the Starlark library graph.
        *   `python/private/common/`: Exclude this entire directory from Gazelle
            processing. It contains legacy file paths and symlinks for older
            Bazel versions, which do not need to be part of the modern Starlark
            library graph.
*   **Package Markers:** Keep `tests/support/whl_from_dir/BUILD.bazel` as a
    nearly empty package marker (matching upstream) to satisfy Bazel's loading
    phase, without defining any targets.

## 3. Target Naming & Compatibility Rules

*   **Naming Convention:** Rename `bzl_library` targets to match the Starlark
    file name (e.g., `foo.bzl` -> `:foo` instead of `:foo_bzl`).
*   **Public Targets:** For public targets, always create deprecated
    backwards-compatibility aliases (e.g., `:foo_bzl` pointing to `:foo`) to
    prevent breaking downstream users.
*   **Private Targets:** If a `bzl_library` is visibility-restricted (private),
    it is **OK to change its name** without creating a compatibility alias.
*   **Visibility of New Targets:** Restrict the visibility of
    `bzl_library` targets created for files that did not previously
    have a `bzl_library` target to `//:__subpackages__`. Do not make
    newly introduced targets public.
*   **Bzlmod-Only Public Targets (`python/extensions/`):** Targets in
    `python/extensions/BUILD.bazel` are Bzlmod-only but are public. We let
    Gazelle process them (generating `:config`, `:pip`, `:python`), but we must
    manually create deprecated backwards-compatibility aliases (`:config_bzl`,
    `:pip_bzl`, `:python_bzl`) to support any legacy references.
*   **Documentation Targets:** When renaming or migrating targets, ensure that
    all documentation targets (such as `bzl_api_docs` in `docs/BUILD.bazel`)
    are updated to reference the new target names (e.g., ensuring
    `//python:py_info` is included).

## 4. Edge Cases & Resolving Overrides

*   **Bzlmod MVS Upgrades:** While manually upgrading dependencies is strictly
    forbidden, automatic transitive upgrades by Bzlmod's Minimal Version
    Selection (MVS) (e.g., upgrading `platforms` or `rules_cc` due to other
    dependencies) can rename or consolidate targets.
*   **Resolve Overrides:** Use `# gazelle:resolve` overrides in the root
    `BUILD.bazel` to map Starlark imports to the correct consolidated external
    targets (e.g., `@rules_cc//cc:core_rules` instead of separate `cc_library`
    and `cc_import` targets).
*   **Omitted External Targets:** If external rulesets omit `bzl_library`
    targets for their setup files, remove them from our dev target `deps` and
    shield our targets with `# keep` to prevent Gazelle from regenerating them.

## 5. Special Directions

*   **Copyrights:** Unless directed by the user otherwise, do not add Bazel
    copyright to new or existing files. Remove any accidentally added
    copyrights.
*   **Patches & Overrides:** Patching dependencies is strictly prohibited.
    Consequently, using `single_version_override` (or any other module
    overrides) to apply patches in `MODULE.bazel` is not permitted.
*   **Sphinxdocs & Gazelle Release Dependency:** `sphinxdocs` and the code
    under `gazelle/` are released separately from `rules_python`. They
    cannot refer to unreleased changes in `rules_python`. Thus, they must
    refer to the old target names in `rules_python` (using the `_bzl`
    suffix, e.g., `@rules_python//python:py_binary_bzl` and
    `@rules_python//python:defs_bzl`).

## 6. Public bzl_library Targets

The following are all the public `bzl_library` targets in the repository (across
both the main module and the Gazelle module) that must be maintained with
backwards-compatibility aliases if they are renamed:

### Main Module (`@rules_python`)
*   `//python:current_py_toolchain_bzl`
*   `//python:defs`
*   `//python:features`
*   `//python:packaging`
*   `//python:pip`
*   `//python:proto`
*   `//python:py_binary`
*   `//python:py_cc_link_params_info`
*   `//python:py_exec_tools_info`
*   `//python:py_exec_tools_toolchain`
*   `//python:py_executable_info`
*   `//python:py_import`
*   `//python:py_info`
*   `//python:py_library`
*   `//python:py_runtime`
*   `//python:py_runtime_info`
*   `//python:py_runtime_pair`
*   `//python:py_test`
*   `//python:python`
*   `//python:repositories`
*   `//python:versions`
*   `//python/cc:py_cc_toolchain`
*   `//python/cc:py_cc_toolchain_info`
*   `//python/entry_points:py_console_script_binary`
*   `//python/extensions:config`
*   `//python/extensions:pip`
*   `//python/extensions:python`
*   `//python/zipapp:py_zipapp_binary`
*   `//python/zipapp:py_zipapp_test`

### Gazelle Module (`@rules_python_gazelle_plugin`)
*   `@rules_python_gazelle_plugin//:def`
*   `@rules_python_gazelle_plugin//manifest:defs`
*   `@rules_python_gazelle_plugin//modules_mapping:def`
*   `@rules_python_gazelle_plugin//python:gazelle_test`

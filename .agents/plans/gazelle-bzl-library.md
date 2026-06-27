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

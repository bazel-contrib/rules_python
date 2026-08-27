---
trigger: glob
description: Documentation formatting, Sphinx MyST style rules, and documentation build correctness
globs: docs/*.md
---

# Documentation Rules

* Act as an expert in tech writing, Sphinx, MyST, and markdown.
* Wrap lines at 80 columns.
* Use hyphens (`-`) in file names instead of underscores (`_`).
* In Sphinx MyST markup, outer directives must have more colons than inner directives.
* When adding `{versionadded}` or `{versionchanged}` sections, add them at the end of the documentation text.
* For unreleased features or attributes, use `VERSION_NEXT_FEATURE` in
  `{versionadded}` / `{versionchanged}` directives. For bug fixes or patch-level
  behavioral adjustments, use `VERSION_NEXT_PATCH` in `{versionchanged}`
  directives.
* **Documentation Build Correctness**: Ensure new `.bzl` files or user-facing APIs are properly registered in documentation build targets (e.g. `//docs:docs` or relevant Starlark API reference generation configs).

---
trigger: glob
description: Documentation formatting, Sphinx MyST style rules, and documentation build correctness
globs: "docs/**,RELEASING.md"
---

# Documentation Rules

* Act as an expert in tech writing, Sphinx, MyST, and markdown.
* Wrap lines at 80 columns.
* Use hyphens (`-`) in file names instead of underscores (`_`).
* Document user-visible behavior, not internal workarounds or implementation
  details.
* **API Docstrings vs. Narrative Docs**: Keep `.bzl` docstrings brief (purpose
  and arguments). Put setup guides and multi-scenario examples in `docs/`, and
  link to them with `{ref}` or `{obj}` instead of repeating rules.
* **How-to Guides (`docs/howto/`)**:
  * Prefer adding sections to an existing topical guide (e.g.
    `docs/howto/build-a-wheel.md`) over creating a separate granular file.
  * Write from the user's task perspective (e.g. "How do I generate the right
    wheel filename for the active Python version?") rather than internal rule
    or provider jargon, and omit low-level implementation parentheticals.
* In Sphinx MyST markup, outer directives must have more colons than inner directives.
* When adding `{versionadded}` or `{versionchanged}` sections, add them at the end of the documentation text.
* For unreleased features or attributes, use `VERSION_NEXT_FEATURE` in
  `{versionadded}` / `{versionchanged}` directives. For bug fixes or patch-level
  behavioral adjustments, use `VERSION_NEXT_PATCH` in `{versionchanged}`
  directives.
* **Documentation Build Correctness**: Ensure new `.bzl` files or user-facing APIs are properly registered in documentation build targets (e.g. `//docs:docs` or relevant Starlark API reference generation configs).
* **`RELEASING.md` Scope**: Keep `RELEASING.md` focused strictly on how to
  perform a release; do not document presubmit CI behavior in it.

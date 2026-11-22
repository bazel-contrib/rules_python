---
trigger: glob
description: >-
  News entry naming, ~20-word brevity, and Sphinx cross-reference conventions
globs: "news/*.md,CHANGELOG.md"
---

@CONTRIBUTING.md

# News Entry Conventions

Adhere to `CONTRIBUTING.md` and the rules below when drafting or reviewing
`news/` entries.

## Applicability
* Add a news entry only for released, user-visible behavior (`added`,
  `changed`, `fixed`, `removed`).
* Omit news entries for:
  * Internal refactoring
  * Test-only changes
  * CI or agent configuration changes
  * Fixes to unreleased code
* Never edit `CHANGELOG.md` directly for unreleased changes.

## Filename
* Name files `news/<id>.<category>.md`, where `<category>` is `added`,
  `changed`, `fixed`, or `removed`.
* Use the GitHub issue or PR number for `<id>` when known; otherwise use a
  short, hyphenated descriptive term (e.g., `my-feature.added.md`) to avoid
  filename collisions.
* Never use generic placeholders like `0000`.

## Brevity (~20 Words) and Content
* Target **~20 words** in 1 concise sentence so `CHANGELOG.md` stays easy to
  skim:
  * Aim for 10–25 words, with a 30-word ceiling excluding any trailing
    issue/PR link.
  * Brief breaking-change migration pointers may use up to the 30-word
    ceiling.
* Prefix with the subsystem in parentheses when applicable (e.g., `(pypi)`,
  `(toolchains)`, `(gazelle)`, `(bzlmod)`), and omit leading bullet points
  (`*` or `-`).
* State high-level, user-visible outcomes (what changed or now works).
* Cut secondary details that belong in API docstrings or `docs/`:
  * Configuration mechanics, flag/attribute combinations, and inline `e.g.`
    walkthroughs
  * Exhaustive lists of variables, attributes, fields, or platforms
  * Internal implementation details, refactoring mechanics, and background
    rationale
  * Secondary edge-case explanations
* Wrap lines at 80 columns.

## Sphinx MyST Cross-References and Issue Links
* Use `` {obj}`<symbol>` `` (or `{attr}` / `{rule}`) only for
  cross-referencable Starlark or Python API symbols. Never wrap metadata files
  (e.g., `RECORD`), file paths, external packages, or CLI tools in `{obj}`.
* Use short `` {flag}`--<name>` `` cross-references for
  `//python/config_settings` flags (e.g., `` {flag}`--coverage` `` instead of
  `--@rules_python//python/config_settings:coverage`); `sphinx_bzl`
  auto-resolves short flag names.
* Append GitHub issue or PR cross-references at the end in Markdown link
  format:
  `([#3283](https://github.com/bazel-contrib/rules_python/issues/3283))`.

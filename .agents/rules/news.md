---
trigger: glob
description: Apply when drafting news entries.
globs: "news/*.md"
---

@CONTRIBUTING.md

# News Entry Conventions

Before drafting any news entry, adhere strictly to the rules in
`CONTRIBUTING.md` above.

## Sphinx MyST Cross-Reference Syntax (`{obj}`)
* Use `{obj}\`<symbol>\`` only for cross-referencable Starlark or Python API
  symbols (rules, macros, targets, providers, attributes, args).
* Never use `{obj}` on metadata files (e.g. `RECORD`), file paths, or tools.

## Content
* State user-visible behavior and outcomes (what now works, what changed).
* Omit internal implementation and refactoring details.

## GitHub Issue Link Formatting
* Append GitHub issue cross-references at the end of news entries in markdown
  link format:
  `([#3283](https://github.com/bazel-contrib/rules_python/issues/3283))`.

## Unreleased and Internal Changes
* Do not add news entries for internal refactoring or fixes to unreleased code.
  News entries are only for released, user-visible behavior.

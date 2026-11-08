---
trigger: glob
description: Apply when drafting news entries.
globs: "news/*.md"
---

@CONTRIBUTING.md

# News Entry Conventions

Before drafting any news entry, adhere strictly to the rules in
`CONTRIBUTING.md` above.

## Filename
* Name files `news/<id>.<category>.md`.
* Use the GitHub issue or PR number for `<id>` when known; otherwise, use a
  short, hyphenated descriptive term (e.g., `my-feature.added.md`) to avoid
  filename collisions.
* Never use generic placeholders like `0000`.

## Brevity and Content
* Write a short snippet (1-2 concise sentences) so the combined `CHANGELOG.md`
  is easy to skim and grok.
* Summarize the capability rather than listing every new variable, attribute, or
  field name (leave exhaustive lists to the API reference docs).
* State high-level, user-visible behavior and outcomes (what now works, what
  changed).
* Omit internal implementation details, refactoring mechanics, and exhaustive
  edge-case explanations (document detailed usage in API docs instead).

## Sphinx MyST Cross-Reference Syntax (`{obj}`)
* Use `{obj}\`<symbol>\`` only for cross-referencable Starlark or Python API
  symbols (rules, macros, targets, providers, attributes, args).
* Never use `{obj}` on metadata files (e.g. `RECORD`), file paths, or tools.

## GitHub Issue Link Formatting
* Append GitHub issue cross-references at the end of news entries in markdown
  link format:
  `([#3283](https://github.com/bazel-contrib/rules_python/issues/3283))`.

## Unreleased and Internal Changes
* Do not add news entries for internal refactoring or fixes to unreleased code.
  News entries are only for released, user-visible behavior.

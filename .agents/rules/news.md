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
* Use `{obj}\`<symbol>\`` in news entries for rules, macros, targets, providers,
  attributes, args, and any other cross-referencable Starlark or Python
  objects.

## GitHub Issue Link Formatting
* Append GitHub issue cross-references at the end of news entries in markdown
  link format:
  `([#3283](https://github.com/bazel-contrib/rules_python/issues/3283))`.

## Unreleased and Internal Changes
* Do not add news entries for internal refactoring or fixes to unreleased code.
  News entries are only for released, user-visible behavior.

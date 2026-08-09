---
trigger: news/*.md
description: Apply when drafting news entries.
---

@CONTRIBUTING.md

# News Entry Conventions

Before drafting any news entry, strictly adhere to the rules in `CONTRIBUTING.md`
above.

## Sphinx MyST Cross-Reference Syntax (`{obj}`)
* Use `{obj}\`<symbol>\`` in news entries for rules, macros, targets, providers,
  attributes, args, and any other cross-referencable Starlark or Python
  objects.

## GitHub Issue Link Formatting
* Append GitHub issue cross-references at the end of news entries in markdown
  link format: `([#3283](https://github.com/bazel-contrib/rules_python/issues/3283))`.

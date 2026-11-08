---
name: create-news
description: Create or update a concise news entry file in `news/` for
  user-visible changes
---

Use this skill when adding or editing a news fragment in `news/`. News entries
are combined into `CHANGELOG.md` at release time and must be short snippets that
are easy to skim and grok.

@.agents/rules/news.md

### Workflow

1. **Determine if a News Entry is Needed**:
   - Create a news file only for released, user-visible changes (`added`,
     `changed`, `fixed`, `removed`).
   - Skip news files for internal refactoring, test-only changes, or fixes to
     unreleased code.
   - Never edit `CHANGELOG.md` directly for unreleased changes.

2. **Choose the Filename (`news/<id>.<category>.md`)**:
   - `<id>`: Use the GitHub issue or PR number if one exists (e.g., `4181`).
     If no issue or PR exists yet, use a short, hyphenated descriptive term
     (e.g., `py-typed-pyi-srcs.added.md`). Never use `0000` or generic
     placeholders.
   - `<category>`: Choose `added`, `changed`, `fixed`, or `removed`.

3. **Draft a Short, Skimmable Snippet**:
   - Keep the entry to 1-2 concise sentences stating *what* changed for users.
   - Prefix with the subsystem in parentheses when applicable (e.g., `(pypi)`,
     `(toolchains)`, `(gazelle)`, `(bzlmod)`).
   - Omit leading bullet points (`*` or `-`).
   - Cut implementation mechanics, internal helper names, and secondary
     edge-case explanations; put detailed usage in API docstrings instead.
   - Wrap lines at 80 columns.
   - Append issue/PR links at the end when applicable:
     `([#1234](https://github.com/bazel-contrib/rules_python/issues/1234))`.

### Examples

**Good (concise and skimmable)**:
```markdown
(toolchains) Added the
{obj}`--@rules_python//python/config_settings:py_pbs_distribution` flag to
select stripped `python-build-standalone` runtime archives
([#4163](https://github.com/bazel-contrib/rules_python/issues/4163)).
```

```markdown
(coverage) Skip lcov report generation when no coverage data is collected.
```

**Bad (too verbose and detailed)**:
```markdown
(pypi) A {obj}`pip.parse` call for a Python version that has no interpreter for
the host platform is now skipped, like a version with no registered toolchain,
instead of failing the whole {obj}`pip` extension. A dependency that lists,
say, Python 3.9 no longer breaks every other hub on hosts that have no CPython
3.9 build, such as Windows on ARM64
([#4184](https://github.com/bazel-contrib/rules_python/issues/4184)).
```
*(Rewrite: `(pypi) Skip {obj}\`pip.parse\` calls for Python versions without a
host interpreter instead of failing the {obj}\`pip\` extension
([#4184](https://github.com/bazel-contrib/rules_python/issues/4184)).`)*

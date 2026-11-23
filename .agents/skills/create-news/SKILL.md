---
name: create-news
description: Create or update a ~20-word news entry file in `news/` for
  user-visible changes
---

Use this skill when adding or editing a news fragment in `news/`. Release
tooling assembles `news/` files into `CHANGELOG.md`, so each entry must follow
`.agents/rules/news.md`.

@.agents/rules/news.md

### Workflow

1. Check `.agents/rules/news.md` to confirm the change requires a
   `news/<id>.<category>.md` file.
2. Draft a single-sentence snippet targeting **~20 words** per
   `.agents/rules/news.md`, then count the words (excluding any trailing
   issue/PR link) and move secondary details to API docstrings or `docs/`.

### Examples

**Good (~10–20 words, high-level and skimmable)**:
```markdown
(toolchains) Added {flag}`--py_pbs_distribution` to select stripped
`python-build-standalone` runtime archives
([#4163](https://github.com/bazel-contrib/rules_python/issues/4163)).
```

```markdown
(coverage) Skip lcov report generation when no coverage data is collected.
```

**Bad (40+ words packing API-doc mechanics and rationale into `news/`)**:
```markdown
(coverage) Added the {flag}`--coverage` flag to use the `coverage` package
locked in the requirements, e.g. `@pypi//coverage`, without configuring the
Python toolchains. It can be a `py_library` that bundles plugins and
`.coveragerc` files, which are merged, and it can be set per target via
`config_settings`
([#3902](https://github.com/bazel-contrib/rules_python/issues/3902)).
```

*Rewrite (11 words, excluding the trailing issue link):*
```markdown
(coverage) Added {flag}`--coverage` to select the coverage package from locked
requirements
([#3902](https://github.com/bazel-contrib/rules_python/issues/3902)).
```

```markdown
(pypi) A {obj}`pip.parse` call for a Python version that has no interpreter for
the host platform is now skipped, like a version with no registered toolchain,
instead of failing the whole {obj}`pip` extension. A dependency that lists,
say, Python 3.9 no longer breaks every other hub on hosts that have no CPython
3.9 build, such as Windows on ARM64
([#4184](https://github.com/bazel-contrib/rules_python/issues/4184)).
```

*Rewrite (15 words, excluding the trailing issue link):*
```markdown
(pypi) Skip {obj}`pip.parse` calls for Python versions without a host
interpreter instead of failing {obj}`pip`
([#4184](https://github.com/bazel-contrib/rules_python/issues/4184)).
```

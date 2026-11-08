---
name: rule-creator
description: Create and format agent rules with proper front matter in the
  workspace
---

Use this skill when you need to create a new rule for the agent in the
workspace.

### Rule File Location

All workspace-specific rules must be created as individual Markdown files under
the `.agents/rules/` directory:
```
.agents/rules/<rule-name>.md
```

### Rule Format

Every rule file must start with a YAML front matter block defining the trigger
condition, followed by the rule content in Markdown.

```yaml
---
trigger: <trigger-condition>
---

# <Rule Title>

<Rule description and directives...>
```

#### Trigger Conditions
*   `always_on`: The rule is always active and must be followed for all tasks.
*   `model_decision`: The agent loads the rule based on its `description` when
    relevant. Prefer `model_decision` for conceptual, architectural, or
    cross-cutting rules (e.g., `pr.md`, `rules_python.md`).
*   `glob`: The rule activates when matching files (`globs:`) are accessed.
    Use for syntax/formatting rules tied to specific file types. `globs` must
    be a quoted, comma-separated string (e.g., `globs: "*.bzl,BUILD.bazel"`),
    never a YAML list/sequence.

### Domain Separation
*   Keep language and tool rule files (`starlark.md`, `bzl.md`, `python.md`,
    `docs.md`) general to those domains.
*   Place `rules_python`-specific Bzlmod, PyPI, and rule API invariants in
    `.agents/rules/rules_python.md`.

### Formatting Guidelines
*   **Line Wrapping:** Wrap all text to 80 columns.
*   **Prose Style (Strunk & White):** Omit needless words. Do not use mannered
    prose or verbose phrasing; state directives directly in active voice.

### Example

To create a rule that prevents adding copyrights:

```markdown
---
trigger: always_on
---

# No Copyrights Rule

Unless directed by the user otherwise, do not add Bazel copyright to new or
existing files.
```

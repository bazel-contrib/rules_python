---
name: rule-creator
description: Create and format agent rules with proper front matter in the workspace
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
*   Custom triggers: You can specify other trigger conditions if the rule only
    applies in certain contexts.

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

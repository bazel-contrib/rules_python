---
name: review-code
description: High-level code review audit of local changes when preparing to
  send a PR for review
trigger: model_decision
---

When preparing to send a Pull Request for review, invoke **separate, concurrent
sub-agents** (`invoke_subagent`), where each sub-agent focuses exclusively on
its assigned checklist category.

**CRITICAL**: Do NOT use a single sub-agent to validate multiple or all
dimensions at once. Each sub-agent must be launched with its own distinct prompt
file from `.agents/skills/review-code/`:

### Audit Checklist & Sub-Agent Prompts

1. **Starlark / Bazel Sub-Agent** (`Role: "Starlark Code Auditor"`):
   - Prompt file:
     `.agents/skills/review-code/review-starlark-prompt.md`
   - Focus: Audits Starlark / Bazel changes (`*.bzl`, `BUILD`, `*.bazel` files)
     in `git diff` against `.agents/rules/bzl.md` and Starlark rules in
     `AGENTS.md`.

2. **Python Code Sub-Agent** (`Role: "Python Code Auditor"`):
   - Prompt file:
     `.agents/skills/review-code/review-python-prompt.md`
   - Focus: Audits Python source and test changes in `git diff` against
     `.agents/rules/python.md` and Python and pytest conventions in `AGENTS.md`.

3. **Documentation Sub-Agent** (`Role: "Documentation Auditor"`):
   - Prompt file:
     `.agents/skills/review-code/review-docs-prompt.md`
   - Focus: Audits documentation (`.md`) changes and docs build targets against
     `.agents/rules/docs.md`, `.agents/rules/news.md`, and `AGENTS.md`.

4. **Contribution Guidelines Sub-Agent** (`Role: "Contributing Auditor"`):
   - Prompt file:
     `.agents/skills/review-code/review-contributing-prompt.md`
   - Focus: Audits changes, requirements updates, directives, and news entry
     files (`news/<id>.<category>.md`) against `CONTRIBUTING.md` and
     `.agents/rules/news.md`.

5. **Project Conventions Sub-Agent** (`Role: "Project Conventions Auditor"`):
   - Prompt file:
     `.agents/skills/review-code/review-agents-prompt.md`
   - Focus: Audits overall workspace compliance against `AGENTS.md`.

6. **Pull Request Standards Sub-Agent** (`Role: "PR Standards Auditor"`):
   - Prompt file:
     `.agents/skills/review-code/review-pr-standards-prompt.md`
   - Focus: Audits PR titles and descriptions against Conventional Commits
     formatting and PR update rules in `CONTRIBUTING.md`.

### Action Instructions
- Launch all sub-agents concurrently using `invoke_subagent`.
- Collect the reports from each sub-agent and report all violations and
  suggested improvements clearly with suggested fixes for the user.
- If all domain audits pass, confirm that the PR is ready for review.

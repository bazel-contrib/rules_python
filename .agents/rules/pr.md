---
trigger: model_decision
description: rules to apply to pull request descriptions
---

@CONTRIBUTING.md

# Pull Request Conventions

Before drafting any pull request description, strictly adhere to the rules in
`CONTRIBUTING.md` above.

## Prevent Agent Oversight of `CONTRIBUTING.md`
* Always include `@CONTRIBUTING.md` in rule definitions so that PR formatting
  rules are injected into context whenever PR workflows run.

## Commit & PR Types
* `fix:` / `feat:`: User-visible changes ONLY.
* `workflow:` / `workflows:`: Internal workflow automation, release tooling, and
  CI scripts (e.g., `workflow(release): ...`).
* `tests:`: Test-only changes and test-helper fixes (never `fix:` or
  `fix(tests):`).

## PR Commit Workflow Invariant
* Once a Pull Request is created, always make new commits or merge commits.
* **NEVER** amend or rebase commits on an active PR branch to avoid breaking
  code review threads.
* **NEVER** include a list of per-file edits or changelog bullet points of
  individual file modifications in PR descriptions or commit messages.
* High-level overview only: state *why* the change is made and *how* at a
  conceptual level. Link related issues (e.g. `Work towards #<issue>`).

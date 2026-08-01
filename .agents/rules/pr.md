---
trigger: model_decision
description: Apply when drafting pull request descriptions.
---

@CONTRIBUTING.md

# Pull Request Conventions

Before drafting any pull request description, strictly adhere to the rules in
`CONTRIBUTING.md` above.

## Prevent Agent Oversight of `CONTRIBUTING.md`
* Always include `@CONTRIBUTING.md` in rule definitions so that PR formatting
  rules are injected into context whenever PR workflows run.

## PR Commit Workflow Invariant
* Once a Pull Request is created, always make new commits or merge commits.
* **NEVER** amend or rebase commits on an active PR branch to avoid breaking
  code review threads.

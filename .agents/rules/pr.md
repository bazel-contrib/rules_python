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
* `build:` / `build(release):`: Internal release tooling
  (`tools/private/release/`), developer workflows, and build scripts. Always
  prefer `build(release):` over `chore:` or `chore(release):`.
* `docs:`: Documentation and issue templates (`.github/ISSUE_TEMPLATE/`).
* `ci:`: `.bazelci` and Buildkite CI configurations.
* `workflow:` / `workflows:`: GitHub Actions workflow configurations
  (`.github/workflows/`).
* `tests:`: Test-only changes and test-helper fixes (never `fix:` or
  `fix(tests):`).
* `agents:` / `agents(<scope>):`: Agent rules, skills, and prompts
  (`.agents/`).
* `refactor:`: Internal refactoring and fixes for unreleased changes. Never use
  `fix:` or `feat:` unless modifying released, user-visible behavior.

## PR Commit Workflow Invariant
* Once a Pull Request is created, always make new commits or merge commits.
* **NEVER** amend or rebase commits on an active PR branch to avoid breaking
  code review threads.
* **PR Metadata Discrepancies**: If a PR title or description diverges from
  the branch's actual scope, notify the user of the discrepancy and ask for
  confirmation before updating GitHub.
* **NEVER** include a list of per-file edits or changelog bullet points of
  individual file modifications in PR descriptions or commit messages.
* High-level overview only: state *why* the change is made and *how* at a
  conceptual level. Link related issues (e.g. `Work towards #<issue>`).
* **Conciseness & Style (Strunk & White)**: Omit needless words. Use clear,
  active, and direct phrasing for *why* and *how*.
* **Preserve Existing Descriptions**: Preserve the author's wording unless
  instructed to change it. Wrap bodies at 72 columns.

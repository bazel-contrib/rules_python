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
  (`dev/release/`), developer workflows, and build scripts. Always
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
* **Open Questions & Follow-Up Items**:
  * Add the `"do not merge"` label to the PR when the PR description contains
    open questions (e.g., `gh pr edit <pr> --repo bazel-contrib/rules_python
    --add-label "do not merge"`).
  * During code review, inspect the PR description and comments for open
    questions, `TODO` items, or "Things we could do / follow-up" notes.
    Evaluate each item against the diff and project rules, flag unresolved
    items with `BLOCKER`, `QUESTION`, or `HUMAN-SIGN-OFF`, and verify the
    `"do not merge"` label is applied if open questions remain.

## PR Review Comments & Thread Resolution
* End every posted PR comment or review reply with an italicized disclosure line
  identifying it as an agent-generated response and indicating whether it was
  automatically generated or user-reviewed/approved.
* After fixing an inline PR review thread, reply with the commit hash and
  explanation (`addPullRequestReviewThreadReply`) and resolve the thread
  (`resolveReviewThread`) via `gh api graphql`, batching at most 3-4 threads per
  request to avoid `502 Bad Gateway` timeouts.

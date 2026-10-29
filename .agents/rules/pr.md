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
* **NEVER** include a list of per-file edits, changelog bullet points of
  individual file modifications, test execution logs/checklists, or AI
  disclosure metadata in PR descriptions or commit messages.
* **AI Disclosure & Comment Etiquette**: Keep the PR description clean for use
  as the merge commit message. After creating a PR, post a separate comment so
  maintainers understand who/what they are interacting with: state the level of
  human oversight and explain how comments on the PR will be handled (whether
  an agent autonomously monitors and replies, whether a human reviews/approves
  agent responses before posting, or whether the human responds directly).
  Never post comments for every CI run or narrate build IDs, commit SHAs, line
  counts, or trivial diff details (e.g., "comment-only"); comment `PTAL` only
  when ready for re-review.
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
* End every posted PR comment or review reply with an italicized disclosure
  line:
  * If the exact comment text was not shown to and approved by the user before
    posting (including automatic PR AI disclosure comments):
    `*This is an automatically generated agent comment.*`
  * Only if the user was shown the exact comment text and explicitly approved
    posting it:
    `*This is an agent-generated comment reviewed and approved by the user.*`
* After fixing an inline PR review thread, reply with the commit hash and
  explanation (`addPullRequestReviewThreadReply`) and resolve the thread
  (`resolveReviewThread`) via `gh api graphql`, batching at most 3-4 threads per
  request to avoid `502 Bad Gateway` timeouts.

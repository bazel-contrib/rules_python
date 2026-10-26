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
   - Focus: Audits Python source, test, and inline script changes in `git diff`
     against `.agents/rules/python.md` and Python and pytest conventions in
     `AGENTS.md`.

3. **Documentation Sub-Agent** (`Role: "Documentation Auditor"`):
   - Prompt file:
     `.agents/skills/review-code/review-docs-prompt.md`
   - Focus: Audits documentation (`.md`) changes and docs build targets against
     `.agents/rules/docs.md` and `AGENTS.md`.

4. **Contribution Guidelines Sub-Agent** (`Role: "Contributing Auditor"`):
   - Prompt file:
     `.agents/skills/review-code/review-contributing-prompt.md`
   - Focus: Audits changes, requirements updates, and version directives against
     `CONTRIBUTING.md`.

5. **Project Conventions Sub-Agent** (`Role: "Project Conventions Auditor"`):
   - Prompt file:
     `.agents/skills/review-code/review-agents-prompt.md`
   - Focus: Audits overall workspace compliance against `AGENTS.md`.

6. **Pull Request Standards Sub-Agent** (`Role: "PR Standards Auditor"`):
   - Prompt file:
     `.agents/skills/review-code/review-pr-standards-prompt.md`
   - Focus: Audits PR titles and descriptions against Conventional Commits
     formatting, PR update rules in `CONTRIBUTING.md`, and open questions or
     "TODO / Things we could do" items in the PR description (ensuring the
     `"do not merge"` label is applied when open questions exist).

7. **GitHub Workflows Sub-Agent** (`Role: "GitHub Workflows Auditor"`):
   - Prompt file:
     `.agents/skills/review-code/review-workflows-prompt.md`
   - Focus: Audits workflow files (`.github/**`) and workflow tests against
     `.agents/rules/github_actions_workflows.md` (e.g. `chmod +x` executable
     permissions, shebangs, action and tool versions,
     `./.github/actions/setup-bazel` wrapper usage, fallback jobs, and shell,
     script, CLI flag, `$GITHUB_OUTPUT`, or workflow-command injection
     vulnerabilities).

8. **`rules_python` Usage Sub-Agent** (`Role: "rules_python Usage Auditor"`):
   - Prompt file:
     `.agents/skills/review-code/review-rules-python-prompt.md`
   - Focus: Audits changes against `.agents/rules/rules_python.md` (e.g.,
     `pip.dep()` declarations in `MODULE.bazel` and `MINIMUM_BAZEL_VERSION`
     bounds).

9. **News Entry Sub-Agent** (`Role: "News Entry Auditor"`):
   - Prompt file:
     `.agents/skills/review-code/review-news-prompt.md`
   - Focus: Audits `news/<id>.<category>.md` files for presence, naming (no
     generic `0000` placeholders), brevity and skimmability, and formatting
     against `.agents/rules/news.md` and
     `.agents/skills/create-news/SKILL.md`.

10. Code Style & Architecture Sub-Agent
    (`Role: "Code Style & Architecture Auditor"`):
    - Prompt file:
      `.agents/skills/review-code/review-code-style-prompt.md`
    - Focus: Audits cross-language code style across all code files (`*.py`,
      `*.sh`, `*.cc`, `*.h`, `*.go`, `*.bzl`, `*.bazel`): file definition order,
      guard clauses, fail-closed `else`, single input form, no unrequested
      knobs/aliases, no speculative validation or defensive `None` checks, no
      nested comprehensions, naming precision, simplification, `keep-sorted`
      markers, and CLI safety annotations.

11. Shell Script Sub-Agent (`Role: "Shell Script Auditor"`):
    - Prompt file:
      `.agents/skills/review-code/review-shell-prompt.md`
    - Focus: Audits `*.sh`, git hooks, and inline shell scripts against
      `.agents/rules/shell.md` and `.agents/rules/code-style.md` (long flags
      and commented short flags, direct shebang invocation, GNU `getopt --name`,
      `(set -x; ...)`, `Modifies:` doc sections, no blind `|| true`, and no `$?`
      checks under `set -e`).

12. Justification & Exception Sub-Agent
    (`Role: "Justification & Exception Auditor"`):
    - Prompt file:
      `.agents/skills/review-code/review-justification-auditor-prompt.md`
    - Focus: Evaluates all stated or missing justifications for rule exceptions
      (such as `sys.path`/`ImportError` probing, lint/type/buildifier
      suppressions, custom timeouts/retries, or review replies claiming a rule
      does not apply), rejecting missing, circular, or inaccurate excuses as
      `SHOULD-FIX` and flagging plausible technical constraints as
      `HUMAN-SIGN-OFF`.

### Action Instructions
- Immediately create a user-facing review artifact named
  `code-review-results.md` in the conversation artifact directory so progress
  is visible right away.
- Have sub-agents run `git diff $(git merge-base HEAD upstream/main)` to audit
  committed and uncommitted branch changes without newer `upstream/main`
  commits.
- Launch all sub-agents concurrently using `invoke_subagent`.
- Update `code-review-results.md` as sub-agent responses come in, applying the
  Synthesis & Anti-Noise Gate (below) and omitting all passing-check prose. Do
  not use bold for the introduction or lead-in of a bulleted list or bullet
  item; use **bold** for any questions the user needs to answer. Structure
  `code-review-results.md` as follows:

  ````markdown
  # Code Review: <Target / PR>

  Verdict: `<PASS | NEEDS_FIXES | NEEDS_HUMAN_SIGN_OFF>` (<N> open, <H>
  needing human sign-off, <M> resolved)

  ## Open Issues

  ### <ID>. [<SEVERITY>] <Short title> — [<file>:<line>](file:///...)
  * Problem: <1-2 sentences stating what is wrong and why.>
  * Proposed Fix:
    ```<lang>
    <replacement snippet or diff>
    ```
  * Draft Comment: `<comment text in user's voice>`
  * Author Response: <If the author replied to this comment thread, quote or
    summarize their response here, bolding any question to answer.>
  * Draft Reply: `<proposed reply in user's voice, if applicable>`

  ## Resolved Issues

  * ~~<ID>. [<SEVERITY>] <Short title> ([<file>:<line>](file:///...))~~ —
    Resolved: <How it was fixed or resolved (e.g., fixed in commit N,
    updated in working copy, or dismissed per reviewer).>

  ## Passing Domains
  <Comma-separated list of audited domains with 0 issues>
  ````
- Whenever an open issue in `code-review-results.md` is resolved (via local
  edit, a new commit, or reviewer decision), move it from `## Open Issues` to
  `## Resolved Issues` (never delete it) and record how it was resolved.
- If the PR author posts a question or reply requiring reviewer input on a
  comment thread, record their response (`* Author Response: ...`) and a
  proposed `* Draft Reply` under the corresponding issue in
  `code-review-results.md`, then prompt the user via `ask_question` (including a
  clickable `[code-review-results.md](file:///...#L<start>-L<end>)` link in the
  `question` prompt text).
- Never auto-resolve a rule exception solely because the author added a
  justification comment or reply. Whenever a justification is present or added,
  use the `Justification & Exception Auditor` to evaluate it, rejecting weak or
  inaccurate justifications as `SHOULD-FIX` and keeping plausible justifications
  open as `[HUMAN-SIGN-OFF]` until the user explicitly signs off.
- Once all sub-agents finish, finalize `code-review-results.md` and provide a
  concise summary with the overall verdict and a clickable markdown link to
  `code-review-results.md` in the response.
- If reviewing a PR belonging to another user and at least one net-new candidate
  comment remains after the Anti-Noise Gate, prompt the user via `ask_question`
  (including a clickable `[code-review-results.md](file:///...)` link in the
  `question` prompt text) to choose whether to:
  1. Post the feedback as non-draft comments
  2. Approve PR and post non-draft comments
  3. Post the feedback as draft comments
  4. Review the feedback
  5. Do not post comments
- If reviewing or re-reviewing a PR belonging to another user and the verdict is
  `PASS` (0 open issues and 0 net-new candidate comments) while the PR is not
  yet approved by the user, prompt the user via `ask_question` (including a
  clickable `[code-review-results.md](file:///...)` link in the `question`
  prompt text) to choose whether to:
  1. Approve PR
  2. Do nothing
- Immediately before posting comments (after `ask_question` returns), re-fetch
  the latest PR description, commits, and review comments (`gh pr view`), move
  any issues addressed in the interim to `## Resolved Issues` in
  `code-review-results.md`, and drop their candidate comments.
- When posting comments or replies to a PR, append an italicized disclosure line
  at the end of each comment:
  `*This is an agent-generated comment reviewed and approved by the user.*` if
  the user reviewed and approved posting the comment, or
  `*This is an automatically generated agent comment.*` if posted without user
  review.

### Synthesis & Anti-Noise Gate (Guardrails)

When aggregating sub-agent findings into `code-review-results.md` and before
posting comments, filter out noise:

1. Starlark is not Python: Do not leak Python complaints into Starlark (`.bzl`,
   `BUILD`, `*.bazel`). Starlark has no `is` operator (`== None` is correct),
   freezes default arguments (mutable defaults are safe), accepts `# @unused` or
   `# buildifier: disable=...` suppressions, and prefers explicit `len()`
   checks. Do not suggest Python stdlib functions.
2. Third-Party, Vendored, & Generated Code: Never nitpick style or structure in
   third-party imported, vendored, lockfile, or generated files (such as
   `*requirements*.txt`, `gazelle_python_manifest.yaml`, or patches). Only flag
   build breakages or license issues.
3. Formatter-Handled Output: Never ask to revert a formatter's output (such as
   `buildifier` or `ruff` quote/comma/order changes, trailing newlines, or
   markdown hard-break backslashes).
4. `TODO` Syntax: Do not complain about `TODO(...)` formatting or demand a
   username or issue number. Drop `TODO` syntax nits entirely.
5. Rule Over-Application:
   - Only flag a redundant comment when it literally restates the code. Never
     remove a "why" rationale or Arrange/Act/Assert test headers.
   - Naming nits must be objective (redundant qualifier, misleading term, or
     cryptic abbreviation), not subjective taste.
   - Do not require docstrings on wrapper macros where the signature is
     forwarded via `**kwargs`, or enforce explicit types when duck-typing is the
     established pattern.
6. Verify Before Claiming: A finding that asserts a behavior must quote the
   exact line(s). If uncertain about external tool or API semantics, phrase it
   as a `QUESTION` ("Does X do Y here?") rather than a factual assertion.
7. No Persona Flourishes in Posted Comments: Review comments posted to GitHub
   must contain only technical review content and the trailing italicized
   agent-generated disclosure line. Never include conversational chat persona
   flourishes (song lyrics, jokes, sassy remarks) in posted review comments.
8. Follow-Up Etiquette: Do not block on explicit "postponed to a follow-up"
   notes or minor out-of-scope follow-ups.
9. No Speculative Defensive Checks: Do not invent hypothetical edge cases (such
   as "if list is empty, indexing raises"). Assume callers provide valid domain
   inputs unless there is concrete evidence otherwise.
10. Specific Test Requests: Do not demand tests vaguely ("please add tests");
    always specify the exact behavior, edge case, or branch that needs testing.
11. Consolidation (>= 15 Findings): If sub-agents produce 15 or more findings
    total, consolidate repeated nits into a single comment ("same here and N
    other places") or omit the lowest-priority formatting nits first without
    suppressing naming precision or simplification findings.
12. Deduplicate Against Existing Comments: Inspect existing PR review comments
    and suppress candidate comments that duplicate feedback already posted.

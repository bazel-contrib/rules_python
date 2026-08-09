---
name: create-pr
description: Propose, draft, or create a pull request by delegating to a
  subagent
---

When proposing, drafting, or creating a Pull Request, you MUST ALWAYS delegate
to a subagent. NEVER create or draft PRs directly in the main conversation.

### Instructions

1. **Code Review Audit**: Launch a subagent with `review-code` to verify
   `git diff` conforms to all rules (news entry in `news/`, line wrapping,
   copyright, conventions, Starlark formatting). Fix any issues before
   proceeding.
2. **Launch Subagent**: Use `invoke_subagent` (`TypeName: "self"`).
3. **Subagent Prompt Instructions**:
   - Follow `CONTRIBUTING.md` and `@/.agents/rules/pr.md`.
   - **PR Title**: Conventional commits format (`agents:` prefix for agent
     rules/skills).
   - **PR Body**: Explain *why* and conceptual *how*. Wrap strictly at 72
     columns max. Omit TAG/CONV.
   - **Artifact Requirements**: Create `pr_info.md` with:
     - **User-facing**: Published directly in the user interface.
     - **Interactive feedback enabled**: Allows selecting lines and leaving
       inline comments on the draft (`RequestFeedback: true`).
     - **User decision choices**: Present choices:
       1. Create a regular PR
       2. Create a draft PR
       3. Provide feedback on the draft text
       4. Discard the draft text
   - **Propose vs. Create**: If proposing or drafting a PR, do NOT run
     `gh pr create`—only create the `pr_info.md` artifact. Only execute
     `gh pr create` when explicitly requested to create the PR.
   - **Targeting Upstream Repo**: When creating, target upstream using
     `--repo bazel-contrib/rules_python` and `--head <fork_owner>:<branch>`.
4. **Return Status**: Direct subagent to report PR number/draft status to
   caller.
5. **Link Artifact Before Asking**: Upon subagent completion, output a
   clickable markdown link to `pr_info.md` before prompting for confirmation.
6. **Interactive Actions**: When presenting choices via `ask_question`, always
   include the clickable markdown link to `pr_info.md` in the `question`
   prompt.

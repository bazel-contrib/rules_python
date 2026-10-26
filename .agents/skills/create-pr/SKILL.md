---
name: create-pr
description: Propose, draft, or create a pull request by delegating to a
  subagent
---

When proposing, drafting, or creating a Pull Request, you MUST ALWAYS delegate
to a subagent. NEVER create or draft PRs directly in the main conversation.

### Instructions

1. **Code Review Subagent**: Before launching the PR subagent, launch a
   subagent (`invoke_subagent`, `TypeName: "self"`) to run the `review-code`
   skill (`.agents/skills/review-code/SKILL.md`). Wait for it to finish and fix
   any issues before proceeding.
2. **Launch PR Subagent**: Use `invoke_subagent` (`TypeName: "self"`).
3. **Subagent Prompt Instructions**:
   - Follow `CONTRIBUTING.md` and `@/.agents/rules/pr.md`.
   - **PR Title**: Conventional commits format (`agents:` prefix for agent
     rules/skills).
   - **PR Body**: Explain *why* and conceptual *how*. Wrap strictly at 72
     columns max. Use concise, active phrasing (Strunk & White).
   - **AI Disclosure Comment**: Draft (and post via `gh pr comment` if creating
     the PR) the AI disclosure comment stating the level of human oversight and
     how PR comments will be handled. When posted automatically during `create
     pr` without prior user review of the comment text, end it with:
     `*This is an automatically generated agent comment.*`
     Only use `*This is an agent-generated comment reviewed and approved by the
     user.*` if the user previously reviewed `pr_info.md` and approved the
     draft text.
   - **Artifact Requirements**: Create `pr_info.md` in the subagent's own
     artifact directory (do not attempt to write to the parent's artifact
     directory) with:
     - PR title, 72-column wrapped body, AI disclosure comment text (and
       comment URL if posted), and PR number/URL (if created).
     - **User decision choices** (include only when proposing/drafting before
       PR creation):
       1. Create a regular PR
       2. Create a draft PR
       3. Provide feedback on the draft text
       4. Discard the draft text
   - **Propose vs. Create**: If proposing or drafting a PR, do NOT run
     `gh pr create` or `gh pr comment`—only create the `pr_info.md` artifact.
     Execute `gh pr create` and `gh pr comment` immediately when explicitly
     requested to create the PR (e.g., `create pr`).
   - **Targeting Upstream Repo**: When creating, target upstream using
     `--repo bazel-contrib/rules_python` and `--head <fork_owner>:<branch>`.
   - **Open Questions Label**: If the PR description contains open questions,
     apply the `"do not merge"` label (`--label "do not merge"`).
4. **Return Status**: Direct subagent to report the PR number/draft status, AI
   disclosure comment URL (if posted), and the absolute file path to its
   `pr_info.md` artifact back to the caller.
5. **Publish and Link Artifact in Main Agent**: Upon subagent completion, read
   the subagent's `pr_info.md` via `view_file`, publish it to the main agent's
   own artifact directory via `write_to_file` (`UserFacing: true`, and
   `RequestFeedback: true` when proposing), and output a clickable markdown
   link to the main agent's `pr_info.md`. When the PR was created immediately,
   summarize the created PR and posted AI disclosure comment in chat; when
   proposing, prompt for confirmation.
6. **Interactive Actions**: When presenting choices via `ask_question`, always
   include the clickable markdown link to `pr_info.md` in the `question`
   prompt.

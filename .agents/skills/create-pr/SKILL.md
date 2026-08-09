---
name: create-pr
description: Propose, draft, or create a pull request by delegating to a
  subagent
---

When creating a Pull Request for local changes or a branch, invoke a subagent
to handle PR creation or description drafting.

### Instructions

1. **Code Review Audit Subagent**: Before drafting or creating a PR, launch a
   subagent to run the `review-code` skill on local changes (`git diff`).
   Verify all checks pass (e.g., news entry in `news/`, `VERSION_NEXT_FEATURE`
   directives, no Bazel copyright headers, line wrapping, Starlark formatting).
   Fix any issues found before proceeding.
2. Launch a subagent using `invoke_subagent` with `TypeName: "self"` (or
   `agentapi new-conversation`).
3. Provide a prompt to the subagent directing it to:
   - Include `@/.agents/rules/pr.md` and read `CONTRIBUTING.md` (specifically
     the sections on **Commit messages and PR descriptions** and
     **Documenting changes**) before drafting.
   - Strictly adhere to `CONTRIBUTING.md` rules for:
     - **PR Title**: Follow conventional commit style and title formatting.
       For agent rules, skills, and system updates, use `agents:` prefix.
     - **PR Body**: Include rationale, high-level summary, and structure.
       **CRITICAL**: Strictly wrap all PR body text at 72 columns max
       (GitHub uses the PR description as the commit message upon merge,
       which reflows text at 72 columns).
     - **Formatting**: Follow repository style guidelines and structure.
   - Create a Markdown artifact (`pr_info.md`) meeting the following
     requirements:
     - **User-facing**: Published so it is presented directly in the user
       interface.
     - **Interactive feedback enabled**: Allows the user to select lines and
       leave inline comments on the draft.
     - **User decision choices**: Ask the user if they want to:
       1. Create a regular PR
       2. Create a draft PR
       3. Provide feedback on the draft text
       4. Discard the draft text
   - **Propose vs. Create**: If the user requested to propose or draft a PR
     description, **do not** run `gh pr create`—just create the `pr_info.md`
     artifact for the user to review. Otherwise, execute `gh pr create` with
     the formatted title and body.
   - **Targeting Upstream Repo**: When executing `gh pr create`, always target
     the upstream repository by passing `--repo bazel-contrib/rules_python` and
     `--head <fork_owner>:<branch_name>`.
4. **Return Status**: Direct the subagent to communicate the PR number or draft
   status back using `send_message` (or `agentapi send-message`) with the
   parent conversation ID, or include it in its final completion response.
5. **Publish Artifact**: Upon receiving the subagent completion message, the
   main agent must publish `pr_info.md` to display the artifact directly in
   the primary user UI.
6. **Interactive Actions**: To present custom action choices to the user
   (e.g., "Create PR", "Create Draft PR"), the main agent can use the
   `ask_question` tool with custom options.

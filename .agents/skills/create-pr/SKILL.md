---
name: create-pr
description: Create a pull request by delegating to a subagent
---

When creating a Pull Request for local changes or a branch, invoke a subagent
to handle PR creation or description drafting.

### Instructions

1. Launch a subagent using `invoke_subagent` with `TypeName: "self"` (or
   `agentapi new-conversation`).
2. Provide a prompt to the subagent directing it to:
   - Read `CONTRIBUTING.md` (specifically the sections on **Commit messages
     and PR descriptions** and **Documenting changes**) before drafting.
   - Strictly adhere to `CONTRIBUTING.md` rules for:
     - **PR Title**: Follow conventional commit style and title formatting.
       For agent rules, skills, and system updates, use `agents:` prefix.
     - **PR Body**: Include rationale, high-level summary, and structure.
     - **Formatting**: Follow repository style guidelines and structure.
   - Create a Markdown artifact (`pr_info.md`) containing the PR title, body,
     and link/metadata so the user can review and comment on it.
   - **Propose vs. Create**: If the user requested to propose or draft a PR
     description, **do not** run `gh pr create`—just create the `pr_info.md`
     artifact for the user to review. Otherwise, execute `gh pr create` with
     the formatted title and body.
   - **Targeting Upstream Repo**: When executing `gh pr create`, always target
     the upstream repository by passing `--repo bazel-contrib/rules_python` and
     `--head <fork_owner>:<branch_name>`.
3. **Return Status**: Direct the subagent to communicate the PR number or draft
   status back using `send_message` (or `agentapi send-message`) with the
   parent conversation ID, or include it in its final completion response.
4. **Publish Artifact**: Upon receiving the subagent completion message, the
   main agent must publish `pr_info.md` to display the artifact directly in
   the primary user UI.
5. **Interactive Actions**: To present custom action choices to the user
   (e.g., "Create PR", "Create Draft PR"), the main agent can use the
   `ask_question` tool with custom options.

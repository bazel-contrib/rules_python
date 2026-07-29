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
     - **PR Body**: Include rationale, high-level summary, and structure.
     - **Formatting**: Follow repository style guidelines and structure.
   - Create a Markdown artifact (`pr_info.md`) containing the PR title, body,
     and link/metadata so the user can review and comment on it.
   - **Propose vs. Create**: If the user requested to propose or draft a PR
     description, **do not** run `gh pr create`—just create the `pr_info.md`
     artifact for the user to review. Otherwise, execute `gh pr create` with
     the formatted title and body.
3. **Return Status**: Direct the subagent to communicate the PR number or draft
   status back using `send_message` (or `agentapi send-message`) with the
   parent conversation ID, or include it in its final completion response.

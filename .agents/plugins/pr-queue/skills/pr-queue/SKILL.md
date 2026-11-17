---
name: pr-queue
description: >-
  Open the PR Queue (/pr-queue) side panel in the agent IDE to view pending
  GitHub PRs and manually launch review-code chats in dedicated Git worktrees.
---

# PR Queue Skill

When the user asks to open `/pr-queue` or the PR Queue panel, output the
one-click sidecar link on its own line:

[📋 PR Queue](sidecar://pr-queue/pr_queue/)

Tell the user:

- The panel does not run automatic reviews or background refreshes; click
  `Refresh` in the panel header to fetch fresh PR state from GitHub.
- For quick terminal output without opening the panel, run:

  ```bash
  ./.agents/plugins/pr-queue/sidecars/pr_queue/fetch_pr_queue.py
  ```

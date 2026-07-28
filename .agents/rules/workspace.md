---
trigger: always_on
---

# Workspace Rules

To avoid confusion from using outdated code states, when starting a new
conversation/session or when first starting a new branch or worktree, unless
explicitly instructed otherwise, ensure the latest upstream code is used as the
basis:
* Fetch `upstream/main` (`git fetch upstream main`).
* Base any new branch or worktree upon `upstream/main` (e.g.,
  `git checkout -b <branch> upstream/main`).
* Run the workspace helper script to configure upstream tracking and safe
  pushing:
  ```bash
  .agents/scripts/setup_triangle_branch.sh <branch>
  ```

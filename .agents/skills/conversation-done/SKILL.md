---
name: conversation-done
description: >-
  Clean up workspace resources (Bazel output base, Git worktree, local/remote
  branches) and delete the agent conversation after successful cleanup
---

# Conversation Done Skill

Cleans up workspace resources created during agent workflows and deletes the
active agent conversation once all cleanup steps succeed.

## Overview

When working on tasks, agents create several workspace and session resources:

1. **Bazel Output Base(s)**: Intermediate build artifacts, execroot trees,
   and running Bazel server and persistent worker processes (consuming tens of
   gigabytes of disk and substantial RAM).
2. **Remote Git Branch**: The feature branch pushed to the user's fork
   (e.g., `origin`).
3. **Local Git Branch**: The feature branch associated with the worktree.
4. **Git Worktree**: The checked-out directory on disk (removed after build
   and branch cleanup steps succeed).
5. **Agent Conversation**: Once all workspace cleanup steps succeed, the script
   prefixes the active conversation (`ANTIGRAVITY_CONVERSATION_ID`) title with
   `"done "` (without duplicating an existing `"done "` prefix, capped at 70
   characters) and permanently deletes the conversation via the local Language
   Server.

## Script Location

The cleanup script is located at:
`./.agents/skills/conversation-done/scripts/cleanup.py`

## Usage

### 1. Clean Up Current Workspace

When invoked from within the agent's worktree:

```bash
# Preview what would be removed:
./.agents/skills/conversation-done/scripts/cleanup.py --dry-run

# Clean up resources (interactive confirmation if TTY):
./.agents/skills/conversation-done/scripts/cleanup.py

# Force cleanup non-interactively (ideal for agents/scripts):
./.agents/skills/conversation-done/scripts/cleanup.py --force
```

### 2. Clean Up by Worktree Path or Branches

```bash
# By worktree path:
./.agents/skills/conversation-done/scripts/cleanup.py \
  --worktree /path/to/worktree --force

# By branch name:
./.agents/skills/conversation-done/scripts/cleanup.py \
  --branches my-feature-branch --force

# By multiple branches:
./.agents/skills/conversation-done/scripts/cleanup.py \
  --branches branch-one branch-two --force
```

### 3. Inspect Active Resources

List all worktrees, branches, and Bazel output bases:

```bash
./.agents/skills/conversation-done/scripts/cleanup.py --list
```

## Selective Cleanup Flags

Fine-tune what gets cleaned up using selective leave flags:

* `--leave-bazel-output-base`: Leave Bazel output bases and build caches
  intact.
* `--leave-worktree`: Leave Git worktree directory on disk.
* `--leave-branch`: Keep local Git branch.
* `--leave-remote`: Do not delete branch from remote fork.
* `--remote <name>`: Override remote destination (default: `pushRemote` or
  `origin`).

## Safety Guarantees

* **Main Repository Protection**: Never removes the primary Git repository
  worktree.
* **Protected Branches**: Never deletes `main`, `master`, `release/*`, or
  `HEAD`.
* **Upstream Remote Protection**: Never deletes branches on `upstream`.
* **No Expunge Rule**: Never runs `bazel clean --expunge`; shuts down servers
  gracefully and deletes the specific output base directory directly.
* **Worktree Deleted After Branch & Build Cleanup**: Removes the Git worktree
  only after Bazel and Git branch cleanup steps succeed, keeping the working
  directory intact on failure.
* **Conversation Deleted Last on Success**: Prefixes the conversation title
  with `"done "` and permanently deletes the active conversation only after all
  workspace cleanup steps succeed, preserving the conversation and transcripts
  if any cleanup step fails.

## Reporting Results

Deleting the active conversation immediately terminates and removes the
session. When running live cleanup from inside an active conversation, state
which resources you will clean up beforehand (or run `--dry-run` first to
preview). In `--dry-run` mode or external invocations without an active
conversation ID, report the deleted (or previewed) resources:

* **Bazel Output Base(s)**: Paths and reclaimed disk space sizes.
* **Remote Git Branch**: Deleted remote branch (`<remote>/<branch>`).
* **Local Git Branch**: Deleted local branch name.
* **Git Worktree**: Removed worktree directory path.
* **Agent Conversation**: Updated `"done "` conversation title and deleted (or
  previewed) conversation ID.

If any resources were skipped, left intact via `--leave-*` flags, or not found,
note that briefly in the summary.

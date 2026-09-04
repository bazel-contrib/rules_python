---
name: conversation-done
description: >-
  Clean up files and resources that aren't part of the agent conversation
  (e.g. Bazel output base, Git worktree, local/remote branches)
---

# Conversation Done Skill

Cleans up external workspace resources created during agent workflows while
preserving agent conversation data, chat history, and brain transcripts.

## Overview

When agents work on tasks, several external resources outside the agent
conversation directory (`~/.gemini/jetski/brain/`) are created:

1. **Bazel Output Base(s)**: Intermediate build artifacts, execroot trees,
   and running Bazel server and persistent worker processes (consuming tens of
   gigabytes of disk and substantial RAM).
2. **Git Worktree**: The checked-out directory on disk.
3. **Local Git Branch**: The feature branch associated with the worktree.
4. **Remote Git Branch**: The feature branch pushed to the user's fork
   (e.g., `origin`).

This skill safely shuts down active build processes and reclaims these
resources without removing the conversation transcript or chat history.

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

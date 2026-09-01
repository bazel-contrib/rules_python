---
name: sync-git-branch-continuously
description: >-
  Runs and manages an automated continuous synchronization loop (pull and push)
  for Git branches. Use when asked to continuously sync, pull, or push a Git
  branch in the background for Git repositories.
---

# Sync Git Branch Continuously

Runs a continuous pull and push loop in the background for Git repositories to
keep a local branch synchronized with remote branches. This helps ensure that
new worktrees based off of main are more up to date.

## Workflow Loop

The sync loop periodically executes:

1.  `git pull --ff-only <pull-from-remote> <pull-from-branch>`
2.  `git push <push-to-remote> HEAD:<push-to-branch>`
3.  Sleeps until timeout (e.g., 60s) or until awakened by an asynchronous
    `SIGUSR1` signal.

## Script Location

The synchronization script is located at:
`scripts/sync_git_branch_continuously.py` under this skill directory.

## Running the Continuous Sync Script

To start the continuous sync script as a background daemon process:

```bash
# Sync active branch with tracking remote every 60s (default):
REPO_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
BRANCH_NAME=$(git branch --show-current 2>/dev/null || echo "default")
./.agents/skills/sync-git-branch-continuously/scripts/\
sync_git_branch_continuously.py \
  > "/tmp/sync_git_${REPO_NAME}_${BRANCH_NAME}.log" 2>&1 &
```

### Script Options

*   `--pull-from-branch <name>`: Remote branch to pull from (defaults to active
    branch).
*   `--push-to-branch <name>`: Remote branch to push to (defaults to active
    branch).
*   `--pull-from-remote <name>`: Remote repository to pull from (defaults to
    tracking remote or `origin`).
*   `--push-to-remote <name>`: Remote repository to push to (defaults to
    tracking remote or `origin`).
*   `--interval <seconds>`: Sleep interval between sync iterations (default:
    `60` seconds).

Example with custom source and target destinations:

```bash
./.agents/skills/sync-git-branch-continuously/scripts/\
sync_git_branch_continuously.py \
  --pull-from-remote upstream --pull-from-branch main \
  --push-to-remote origin --push-to-branch feature \
  --interval 30 \
  > "/tmp/sync_git_main.log" 2>&1 &
```

## Asynchronous Sync Triggers (Signals)

Other processes or agent conversations can asynchronously wake up the daemon
and trigger an immediate pull/push cycle without waiting for the interval to
expire:

```bash
# By PID:
kill -USR1 <PID>

# Or by matching process name:
pkill -USR1 -f "sync_git_branch_continuously.py"
```

## Monitoring & Logs

To check the status or inspect the output of the active background sync loop:

```bash
tail -n 20 "/tmp/sync_git_${REPO_NAME}_${BRANCH_NAME}.log"
```

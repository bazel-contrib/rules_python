# PR Queue Plugin

Side panel UI (`sidecar://pr-queue/pr_queue/`) showing pending GitHub pull
requests with buttons to launch manual code reviews in isolated Git worktrees.

## Behavior

- Displays open GitHub PRs filtered by review status, author, draft state, age,
  or custom search query using the `gh` CLI.
- Fetches on demand without automatic reviews or background polling.
- Looking up a number shows live PR details (or detects asynchronously if a
  missing number is an issue), matching review chats, and launch actions.
- Clicking a PR review button creates or updates a dedicated Git worktree at the
  PR head commit and starts a new conversation running
  `.agents/skills/review-code/SKILL.md`.

## Requirements

- Python 3.13 or higher on `PATH`.
- Authenticated `gh` CLI (`gh auth status`) with access to the target repo.
- A local Git clone of the target repo containing an `upstream` (or `origin`)
  remote so review worktrees can be created from `refs/pull/<N>/head`.
- Global registration in `~/.gemini/config/plugins/pr-queue` (for example via a
  symlink to this directory) so the agent IDE starts `pr-queue/pr_queue`.

## Files

- `plugin.json`: Plugin manifest.
- `rules/AGENTS.md`: Rule surfacing `[📋 PR Queue](sidecar://pr-queue/pr_queue/)`
  when `/pr-queue` is requested.
- `skills/pr-queue/SKILL.md`: `/pr-queue` skill instructions.
- `sidecars/pr_queue/BUILD.bazel`: Bazel library and test targets for the
  sidecar.
- `sidecars/pr_queue/sidecar.json`: Sidecar registration and UI view config.
- `sidecars/pr_queue/fetch_pr_queue.py`: `gh`-based PR queue fetcher and
  filter CLI.
- `sidecars/pr_queue/state_store.py`: Validated config and JSON state storage.
- `sidecars/pr_queue/git_worktree.py`: Git repo detection and PR worktree setup.
- `sidecars/pr_queue/ls_client.py`: Loopback Language Server RPC client.
- `sidecars/pr_queue/server.py`: HTTP backend serving the UI, cached PR queue,
  PR/issue and review chat lookup, and worktree/chat launcher.
- `sidecars/pr_queue/index.html`: Adaptive dark/light side panel frontend.
- `sidecars/pr_queue/fetch_pr_queue_test.py`: Unit tests for `fetch_pr_queue`.
- `sidecars/pr_queue/server_test.py`: Unit tests for `server`, `state_store`,
  `git_worktree`, and `ls_client`.

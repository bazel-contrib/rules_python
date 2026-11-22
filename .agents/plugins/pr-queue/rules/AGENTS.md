# PR Queue Plugin Rule

- The `pr-queue` UI plugin (`sidecar://pr-queue/pr_queue/`) runs as a background
  sidecar in the agent IDE.
- When the user types `/pr-queue` or asks to open the PR Queue plugin, surface
  the one-click pill `[📋 PR Queue](sidecar://pr-queue/pr_queue/)`.
- Do not include `[📋 PR Queue](sidecar://pr-queue/pr_queue/)` on unrelated
  turns.

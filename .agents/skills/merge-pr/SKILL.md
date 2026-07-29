---
name: merge-pr
description: Merge a pull request into main, monitoring the merge queue, retrying CI flakes, and re-enqueuing if necessary
---

When the user asks to merge a pull request (e.g., "merge PR <number>", "merge this PR", or monitor its merge):

1. **Enqueue for Merge**: Run `gh pr merge <pr_number> --auto --squash` to enable auto-merge or add the pull request to the merge queue.
2. **Invoke a Background Shepherd**: Launch a background subagent with the role `Merge PR Shepherd` to continuously watch the PR until it merges.
3. **Leverage Existing CI Skills**: 
   - Have the subagent use the **`monitor-ci-results`** skill to watch for CI check failures and generate analysis reports.
   - Have the subagent use the **`buildkite-retry-job`** skill (`retry_buildkite_jobs.py <pr_number>`) to automatically retry any transient network flakes (e.g., HTTP 504 gateway timeouts, downloader errors).
4. **Queue Shepherding**: Periodically check `gh pr view <pr_number> --json state,autoMergeRequest`. While `state` is `"OPEN"`, ensure auto-merge is enabled / queued by running `gh pr merge <pr_number> --auto --squash`. If `autoMergeRequest` is null (e.g., ejected from the merge queue due to a CI flake in the temporary queue branch), re-enqueue it for merge by running `gh pr merge <pr_number> --auto --squash` once checks are retried or green.
5. **Completion Notification**: Once `state` becomes `"MERGED"`, send a high-priority message back to the parent conversation.

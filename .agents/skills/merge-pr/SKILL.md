---
name: merge-pr
description: Merge a pull request into main, monitoring the merge queue,
  retrying CI flakes, and re-enqueuing if necessary
---

When the user asks to merge a pull request (e.g., "merge PR <number>", "merge
this PR", or monitor its merge):

1. **Enqueue for Merge**: Run
   `gh pr merge <pr_number> --repo bazel-contrib/rules_python --auto --squash`.
   - **Force / Admin Merge**: **CRITICAL**: Only pass `--admin` (e.g.,
     `gh pr merge <pr_number> --repo bazel-contrib/rules_python --admin --squash`)
     with explicit user consent ("force merge", "admin merge", or "merge
     immediately" once CI passes and only `REVIEW_REQUIRED` blocks). Never pass
     `--admin` while CI is pending or failing unless told to bypass CI.
2. **Invoke a Background Shepherd**: Launch a background subagent with the role
   `Merge PR Shepherd` to continuously watch the PR until it merges.
3. **Leverage Existing CI Skills**: 
   - Have the subagent use the **`monitor-ci-results`** skill to watch for CI
     check failures and generate analysis reports.
   - Have the subagent use the **`buildkite-retry-job`** skill
     (`retry_buildkite_jobs.py <pr_number>`) to automatically retry any
     transient network flakes (e.g., HTTP 504 gateway timeouts, downloader
     errors).
   - **Soft-Failing Jobs**: Experimental Buildkite jobs (e.g. `*rolling*`
     Bazel) are non-blocking soft failures; do not treat them as merge blockers.
   - When the PR is queued, actively discover the merge queue branch via
     `gh api repos/:owner/:repo/branches --jq '.[].name | select(test("gh-readonly-queue/.*/pr-<pr_number>-"))'`
     and monitor commit statuses/Buildkite builds running on that temporary
     branch.
4. **Queue Shepherding**: Periodically check
   `gh pr view <pr_number> --repo bazel-contrib/rules_python --json
   state,autoMergeRequest,mergeStateStatus,mergeable`. While `state` is
   `"OPEN"`, if `autoMergeRequest` is `null` and no
   `gh-readonly-queue/.*/pr-<pr_number>-` branch exists, re-enqueue with
   `gh pr merge <pr_number> --repo bazel-contrib/rules_python --auto --squash`
   once checks are green.
5. **Completion Notification**: Once `state` becomes `"MERGED"`, send a
   high-priority message back to the parent conversation.

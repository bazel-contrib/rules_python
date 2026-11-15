---
name: merge-pr
description: Merge a pull request into main, monitoring the merge queue,
  retrying CI flakes, and re-enqueuing if necessary
---

When the user asks to merge a pull request (e.g., "merge PR <number>", "merge
this PR", or monitor its merge):

1. **Check Mergeability & Enqueue for Merge**:
   - First check `gh pr view <pr_number> --repo bazel-contrib/rules_python
     --json isDraft,mergeable,mergeStateStatus`. `gh pr merge --auto` exits `0`
     even when `mergeable` is `"CONFLICTING"` (`mergeStateStatus: "DIRTY"`),
     which prevents the PR from ever entering the merge queue. If conflicting,
     either merge `upstream/main` and push (if authorized) or report the
     conflict immediately.
   - Run `gh pr merge <pr_number> --repo bazel-contrib/rules_python --auto
     --squash`.
   - **Draft PRs**: If the PR is a draft (`isDraft: true`), mark it ready for
     review first via `gh pr ready <pr_number> --repo
     bazel-contrib/rules_python` (otherwise `gh pr merge` fails with
     `Pull Request is still a draft`). Run `gh pr ready` before pushing final
     commits so external `pull_request` webhooks trigger; if external checks do
     not register on head, run `gh pr close <pr_number> && gh pr reopen
     <pr_number>`.
   - **Force / Admin Merge**: **CRITICAL**: Only pass `--admin` (e.g.,
     `gh pr merge <pr_number> --repo bazel-contrib/rules_python --admin
     --squash`) with explicit user consent ("force merge", "admin merge", or
     "merge immediately" once CI passes and only `REVIEW_REQUIRED` blocks).
     Never pass `--admin` while CI is pending or failing unless told to bypass
     CI.
   - **No `--delete-branch` (`-d`)**: Never pass `-d` or `--delete-branch` to
     `gh pr merge`; it fails when a merge queue is enabled on the repository.
2. **Invoke a Background Shepherd**: Launch a background subagent with the role
   `Merge PR Shepherd` to continuously watch the PR until it merges.
   - If a `monitor_remote_ci.py <pr_number>` background task is currently
     running in the parent conversation, stop it via `manage_task` first so
     `Merge PR Shepherd` can acquire `.monitored_pr_<pr_number>.lock` and
     receive CI failure notifications directly.
3. **Leverage Existing CI Skills**:
   - Have the subagent use the **`monitor-ci-results`** skill to watch for CI
     check failures and generate analysis reports.
   - Have the subagent use the **`retry-ci-job`** skill
     (`retry_ci_jobs.py --pr <pr_number>`) to automatically retry any
     transient network flakes (e.g., HTTP 504 gateway timeouts, downloader
     errors, `setup-bazel` `Unable to find Bazelisk version` errors) and
     unblock manual approval steps.
   - **Blocked Builds (CI Config Approval)**: When the PR changes a file under
     `.bazelci/` or a `.yml` file outside `.github/`, Buildkite blocks the
     build until manually approved. Approve and unblock it immediately via
     `./.agents/skills/retry-ci-job/scripts/retry_ci_jobs.py
     --pr <pr_number> --unblock` (or `bk job unblock <job_id> --no-input`) so CI
     does not sit blocked indefinitely.
   - **Soft-Failing Jobs**: Experimental Buildkite jobs (e.g. `*rolling*`
     Bazel) are non-blocking soft failures; do not treat them as merge blockers.
   - When the PR is queued, actively discover the merge queue branch via
     `gh api repos/:owner/:repo/branches --jq` with
     `'.[].name | select(test("gh-readonly-queue/.*/pr-<pr_number>-"))'`
     and monitor commit statuses/Buildkite builds running on that temporary
     branch.
   - **Blocked Merge Queue Builds**: If the PR changes a file under
     `.bazelci/` or a `.yml` file outside `.github/`, the merge queue build
     is blocked again, even with the `presubmit-auto-run` label, and
     `monitor_remote_ci.py` doesn't watch it. Find it with `bk build list
     --pipeline bazel/rules-python-python --branch <queue_branch> --json |
     jq '.[] | {number, state, blocked}'`, then unblock it with
     `./.agents/skills/retry-ci-job/scripts/retry_ci_jobs.py
     --buildkite-build bazel/rules-python-python/<build_number> --unblock`.
     `--pr <pr_number>` resolves to the PR's build, not the queue build.
4. **Queue Shepherding**: Periodically check
   `gh pr view <pr_number> --repo bazel-contrib/rules_python --json
   state,autoMergeRequest,mergeStateStatus,mergeable`. While `state` is
   `"OPEN"`, if `autoMergeRequest` is `null` and no
   `gh-readonly-queue/.*/pr-<pr_number>-` branch exists, re-enqueue with
   `gh pr merge <pr_number> --repo bazel-contrib/rules_python --auto --squash`
   once checks are green.
5. **Completion Notification**: Once `state` becomes `"MERGED"`, send a
   high-priority message back to the parent conversation.

---
name: monitor-ci-results
description: Monitor remote CI results for a PR and autonomously launch
  subagents to analyze CI failures
---

When the user requests to monitor remote CI results or watch a pull request,
or when monitoring CI after PR updates:

> **Note**: `monitor_remote_ci.py` is a single long-running continuous task.
> It continuously watches all current and future CI runs for the PR. Do NOT
> launch duplicate monitoring jobs for the same PR.

1. **Check Existing Process**: Check if a monitor script is already running for
   **this specific PR** using
   `pgrep -af "[m]onitor_remote_ci.py <pr_number>"`. Do NOT use a generic grep
   without `<pr_number>`, as other active agent conversations may be monitoring
   different PRs concurrently. If one is already running for this PR, do not
   start another instance. Run `pgrep` as a standalone command—do NOT chain it
   with `|| ... monitor_remote_ci.py <pr_number>` in a single shell invocation,
   as `pgrep -af` will match the parent `bash -c` command string and exit `0`.
2. **Launch Monitoring Script**: If no monitor process is active for
   `<pr_number>`, launch the script via `run_command` with `IsDaemon: true` and
   `WaitMsBeforeAsync: 500` (do NOT append a trailing `&`, which causes the
   shell to exit immediately and kills the background process):
```bash
./.agents/skills/monitor-ci-results/scripts/monitor_remote_ci.py \
  <pr_number> "<your_conversation_id>"
```

### ✨ Autonomous Subagent Orchestration
1. **Background Polling**: `monitor_remote_ci.py` continuously polls both
   GitHub PR checks and Buildkite workflow executions in the background across
   new commits and CI re-runs.
2. **Blocked Jobs (`.bazelci/presubmit.yml` Approval)**: When a Buildkite build
   is blocked on a manual approval step (e.g., when `.bazelci/presubmit.yml` is
   modified), `monitor_remote_ci.py` automatically approves and unblocks it via
   `bk job unblock <job_id> --no-input` so CI does not sit blocked. If
   automatic unblocking fails, it notifies the conversation via
   `agentapi send-message`; unblock Buildkite jobs using the
   `retry-ci-job` skill (`retry_ci_jobs.py --pr <pr_number>
   --unblock`).
3. **Failure Reporting**: When any GitHub check or Buildkite job completes
   with errors, `monitor_remote_ci.py` dispatches a high-priority notification
   message reporting the failed check back to your conversation.
   - Soft failures (e.g. `*rolling*` Bazel) are non-blocking warnings; ignore.
4. **Subagent Analysis**: Upon receiving a failure notification message from
   the monitoring script, immediately launch a separate subagent using the
   `invoke_subagent` tool with the role "CI Failure Analyzer" to run the
   `analyze-ci-failure` skill on the reported failure.
5. **Autonomous Flake Retry**: If the CI Failure Analyzer subagent confirms
   that the failure is a transient infrastructure or network flake (e.g. disk
   I/O error, 504 gateway, sandbox initialization failure, or `setup-bazel`
   failing with `Unable to find Bazelisk version`), **immediately and
   autonomously** launch a separate subagent using `invoke_subagent` with the
   role "CI Job Retrier" and the prompt template in
   `.agents/skills/monitor-ci-results/retry-job-prompt.md` to run the
   `retry-ci-job` skill for `<pr_number>`. Do not execute the script
   directly; use the subagent and skill orchestration instead. Continue
   monitoring without pausing to ask the user.

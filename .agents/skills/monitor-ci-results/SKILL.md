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
   **this specific PR** using `pgrep -f "monitor_remote_ci.py <pr_number>"`. Do
   NOT use a generic grep without `<pr_number>`, as other active agent
   conversations may be monitoring different PRs concurrently. If one is
   already running for this PR, do not start another instance.
2. **Launch Monitoring Script**: If no monitor process is active for
   `<pr_number>`, launch the script in the background:
```bash
./.agents/skills/monitor-ci-results/scripts/monitor_remote_ci.py \
  <pr_number> "<your_conversation_id>" &
```

### ✨ Autonomous Subagent Orchestration
1. **Background Polling**: `monitor_remote_ci.py` continuously polls both
   GitHub PR checks and Buildkite workflow executions in the background across
   new commits and CI re-runs.
2. **Blocked Jobs**: When a Buildkite job or GitHub check is in a blocked state
   waiting for user confirmation, it dispatches a notification via `agentapi
   send-message` so the user is alerted to confirm running the job.
3. **Failure Reporting**: When any GitHub check or Buildkite job completes
   with errors, `monitor_remote_ci.py` dispatches a high-priority notification
   message reporting the failed check back to your conversation.
4. **Subagent Analysis**: Upon receiving a failure notification message from
   the monitoring script, immediately launch a separate subagent using the
   `invoke_subagent` tool with the role "CI Failure Analyzer" to run the
   `analyze-ci-failure` skill on the reported failure.
5. **Autonomous Flake Retry**: If the CI Failure Analyzer subagent confirms
   that the failure is a transient infrastructure or network flake (e.g. disk
   I/O error, 504 gateway, sandbox initialization failure), **immediately and
   autonomously** launch a separate subagent using `invoke_subagent` with the
   role "CI Job Retrier" and the prompt template in
   `.agents/skills/monitor-ci-results/retry-job-prompt.md` to run the
   `buildkite-retry-job` skill for `<pr_number>`. Do not execute the script
   directly; use the subagent and skill orchestration instead. Continue
   monitoring without pausing to ask the user.

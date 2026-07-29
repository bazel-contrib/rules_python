---
name: monitor-ci-results
description: Monitor CI for PRs and notify of status
---

When the user requests to monitor remote CI results or watch a pull request,
invoke `scripts/monitor_remote_ci.py <pr_number> <your_conversation_id>`.

This long-running monitoring service runs in the background and continuously
polls both GitHub PR checks and Buildkite workflow executions.

### ✨ Autonomous Failure and Blocked Job Orchestration
1. **Blocked Jobs**: When a Buildkite job or GitHub check is in a blocked
   state waiting for user confirmation, it dispatches a notification via
   `agentapi send-message` so the user is alerted to confirm running the job.
2. **Failure Analysis**: When any CI job completes with errors or returns a
   non-zero exit code:
   - It automatically downloads the raw CI log file to `ci_logs/`.
   - It launches an independent background analyzer script
     (`analyze_ci_failure.py`).
   - It authors a structured Markdown plan to fix the failure.
   - It natively dispatches a high-priority notification back to your active
     agent conversation using `agentapi send-message`!

### Example Invocation
```bash
./scripts/monitor_remote_ci.py 3812 "0be435bd-96aa-4e1b-9c6f-727b31e80fa0" &
```
*Note: Always include the trailing `&` when launching the monitoring script via
tool calls to ensure it runs as a detached background task without blocking
foreground execution.*

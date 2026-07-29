---
name: monitor-ci-results
description: Monitor remote CI results for a PR and autonomously launch
  subagents to analyze CI failures
---

When the user requests to monitor remote CI results or watch a pull request,
launch the monitoring script in the background:
```bash
./.agents/skills/monitor-ci-results/scripts/monitor_remote_ci.py \
  <pr_number> "<your_conversation_id>" &
```

### ✨ Autonomous Subagent Orchestration
1. **Background Polling**: `monitor_remote_ci.py` continuously polls both
   GitHub PR checks and Buildkite workflow executions in the background.
2. **Blocked Jobs**: When a Buildkite job or GitHub check is in a blocked
   state waiting for user confirmation, it dispatches a notification via
   `agentapi send-message` so the user is alerted to confirm running the job.
3. **Failure Reporting**: When any GitHub check or Buildkite job completes
   with errors, `monitor_remote_ci.py` dispatches a high-priority notification
   message reporting the failed check back to your conversation.
4. **Subagent Analysis**: Upon receiving a failure notification message from
   the monitoring script, immediately launch a separate subagent using the
   `invoke_subagent` tool with the role "CI Failure Analyzer" to run the
   `analyze-ci-failure` skill on the reported failure.

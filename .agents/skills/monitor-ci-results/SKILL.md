---
name: monitor-ci-results
description: Monitor remote CI results for a PR and autonomously trigger log analysis upon failures
---

When the user requests to monitor remote CI results or watch a pull request, invoke `scripts/monitor_remote_ci.py <pr_number> <your_conversation_id>`.

This long-running monitoring service runs in the background and continuously polls both GitHub PR checks and Buildkite workflow executions.

### ✨ Autonomous Failure Orchestration
When any CI job completes with errors or returns a non-zero exit code:
1. It automatically downloads the raw CI log file to `ci_logs/`.
2. It launches an independent background analyzer script (`analyze_ci_failure.py`).
3. It authors a beautifully structured Markdown suggested plan for how to fix the failure.
4. It natively dispatches a high-priority notification message back to your active agent conversation (containing the downloaded log path and fix plan) using `agentapi send-message`!

### Example Invocation
```bash
./scripts/monitor_remote_ci.py 3812 "0be435bd-96aa-4e1b-9c6f-727b31e80fa0" &
```

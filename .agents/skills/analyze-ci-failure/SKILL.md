---
name: analyze-ci-failure
description: Download and analyze a CI failure log to construct an actionable suggested fix plan and report back
---

When a CI monitoring workflow alerts you to a failed Buildkite job or GitHub check, invoke this skill by running:
```bash
./.agents/skills/analyze-ci-failure/scripts/analyze_ci_failure.py "<job_name>" "<build_id_or_log_url>" "<job_id>" "<your_conversation_id>"
```

### ✨ What this Skill Does
1. **Resolves Log**: Automatically resolves the Buildkite job download URL or locates existing local log artifacts.
2. **Downloads & Ingests**: Fetches the full raw CI log file and saves it locally.
3. **Smart Error Extraction**: Scans the log lines for critical failure signatures (`Traceback`, `ERROR:`, `FAILED:`, missing packages, compiler aborts).
4. **Fix Plan Synthesis**: Constructs a beautifully structured Markdown suggested plan on how to resolve the root cause.
5. **Natively Notifies**: Dispatches a high-priority summary notification message back to your active agent conversation via `agentapi send-message`!

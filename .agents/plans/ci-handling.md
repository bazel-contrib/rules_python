# Plan: Autonomous CI Failure Handling for PR #3852

This plan outlines the strategy and workflow for autonomously monitoring,
diagnosing, and resolving CI failures for PR #3852, ensuring a rapid and
reliable path to merging while handling known network flakiness.

## 1. Objective

Autonomously oversee the CI lifecycle for PR #3852, immediately detecting
failures, diagnosing their root causes, and applying resolutions (either
retrying flakes or fixing code/configuration errors) to minimize manual
intervention.

## 2. Automated Monitoring

*   **Continuous Polling:** We launch a long-running background monitoring
    service (`monitor_remote_ci.py`) dedicated to PR #3852.
*   **Scope:** This service continuously monitors both GitHub PR checks and
    Buildkite workflow executions.
*   **Trigger:** The service runs continuously in the background and alerts the
    main agent conversation immediately upon any job failure.

## 3. Autonomous Diagnosis

When any CI job completes with a non-zero exit code or errors:
1.  **Log Retrieval:** The monitoring service automatically downloads the raw
    CI log file to `ci_logs/`.
2.  **Failure Analysis:** The service triggers the `analyze_ci_failure.py`
    diagnostic tool.
3.  **Synthesis:** The analyzer scans the logs for failure signatures
    (tracebacks, compiler aborts, network timeouts) and synthesizes an
    actionable, structured Markdown fix plan.
4.  **Notification:** The analyzer dispatches a high-priority notification
    containing the log path and the fix plan back to the active agent
    conversation.

## 4. Resolution Strategy

We categorize failures into two types and address them as follows:

### Category A: Infrastructure & Network Flakes
*   **Identified by:** 504 Gateway errors, fetch timeouts, or unresolved external
    repository downloads.
*   **Resolution:**
    *   **Retries:** If Buildkite permissions allow, we autonomously retry the
        failed job. If not, we notify the user to trigger a manual retry.
    *   **Timeout Scaling:** If timeouts persist, we modify `.bazelrc` to
        increase `--http_timeout_scaling` or repository downloader retries.
    *   **Mirroring:** If a dependency download fails, we check if it is
        available on `mirror.bazel.build`. If so, we add it to
        `downloader_config.cfg` and push the update.

### Category B: Code & Test Failures
*   **Identified by:** Compilation errors, unit test assertion failures, or
    lint/style violations.
*   **Resolution:**
    *   **Apply Fix:** We analyze the generated fix plan, apply the necessary
        code corrections locally, and run the validation suite (`bazel test
        //...`).
    *   **Push:** Once verified green locally, we commit and push the fix
        directly to the PR branch to trigger a new CI run.

## 5. Execution

The monitoring service is launched immediately upon updating the PR and runs
until the PR is merged or closed.

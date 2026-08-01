---
name: buildkite-retry-job
description: Retry failed Buildkite jobs individually or rebuild full builds
---

Use `scripts/retry_buildkite_jobs.py` to retry individual jobs or rebuild full
Buildkite builds.

### Retrying Modes

1. **Job-Level Retry (Default for failed jobs)**:
   Retries only specific failing jobs via `bk job retry <job_id>`:
   ```bash
   ./.agents/skills/buildkite-retry-job/scripts/retry_buildkite_jobs.py <pr_number_or_url>
   ```

2. **Retry Specific Jobs by Name or ID**:
   ```bash
   ./.agents/skills/buildkite-retry-job/scripts/retry_buildkite_jobs.py <pr_number> --jobs "compile_pip_requirements"
   ./.agents/skills/buildkite-retry-job/scripts/retry_buildkite_jobs.py --job-id <job_uuid>
   ```

3. **Rebuild Full Build**:
   Re-runs the entire pipeline build from scratch via `bk build rebuild`:
   ```bash
   ./.agents/skills/buildkite-retry-job/scripts/retry_buildkite_jobs.py <pr_number> --rebuild
   ```

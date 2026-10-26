---
name: retry-ci-job
description: Retry failed Buildkite or GitHub Actions jobs, unblock manual
  approval steps, or rebuild full builds
---

Use `scripts/retry_ci_jobs.py` to retry individual Buildkite or GitHub Actions
jobs, unblock manual approval steps (such as `.bazelci/presubmit.yml` changes),
or rebuild full builds.

When a GitHub Actions job fails early (for example, `Setup Bazel` failing with
`Error: Unable to find Bazelisk version ...` due to a transient network error)
while sibling matrix jobs in the same workflow run are still running, GitHub
rejects rerun requests until the parent workflow run completes. The script
automatically waits for an in-progress workflow run to finish before triggering
`gh run rerun`.

### Retrying & Unblocking Modes

1. **Default Retry & Unblock (by PR, URL, or Buildkite Build)**:
   Unblocks any blocked Buildkite manual approval steps (`bk job unblock
   <job_id> --no-input`), retries specific failing Buildkite jobs (`bk job
   retry <job_id>`), and reruns failing GitHub Actions jobs/runs (`gh run
   rerun`):
   ```bash
   ./.agents/skills/retry-ci-job/scripts/retry_ci_jobs.py \
     --pr <pr_number>
   ./.agents/skills/retry-ci-job/scripts/retry_ci_jobs.py \
     --url "https://github.com/<owner>/<repo>/actions/runs/<run_id>/job/<id>"
   ./.agents/skills/retry-ci-job/scripts/retry_ci_jobs.py \
     --buildkite-build "<org>/<pipeline>/<build_number>"
   ```

2. **Unblock Manual Approval Steps (e.g. `.bazelci/presubmit.yml` changes)**:
   Approves and unblocks blocked manual approval steps without retrying or
   rebuilding other jobs:
   ```bash
   ./.agents/skills/retry-ci-job/scripts/retry_ci_jobs.py \
     --pr <pr_number> --unblock
   ```

3. **Retry Specific Jobs by Name or ID**:
   Retries matching Buildkite or GitHub Actions jobs by name/regex pattern,
   Buildkite job UUID, or numeric GitHub Actions job ID:
   ```bash
   ./.agents/skills/retry-ci-job/scripts/retry_ci_jobs.py \
     --pr <pr_number> --jobs "compile_pip_requirements"
   ./.agents/skills/retry-ci-job/scripts/retry_ci_jobs.py \
     --pr <pr_number> --jobs "Build linux"
   ./.agents/skills/retry-ci-job/scripts/retry_ci_jobs.py \
     --buildkite-job-id <job_uuid>
   ./.agents/skills/retry-ci-job/scripts/retry_ci_jobs.py \
     --github-job-id <github_job_id>
   ```

4. **Rebuild Full Build**:
   Re-runs the entire pipeline/workflow build from scratch via `bk build
   rebuild` or `gh run rerun`:
   ```bash
   ./.agents/skills/retry-ci-job/scripts/retry_ci_jobs.py \
     --pr <pr_number> --rebuild
   ```

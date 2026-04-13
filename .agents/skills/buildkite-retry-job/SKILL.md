---
name: buildkite-retry-job
description: Retry a failed build kite job
---

Use `scripts/retry_buildkite_jobs.py` to retry a job. This is best used
when there are network failures.

example:

```
retry_buildkite_jobs.py org pipeline build
```

The `--jobs` flag can be used to retry specific jobs.

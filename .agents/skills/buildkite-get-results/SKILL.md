---
name: buildkite-get-results
description: Gets buildkite build results
---

Pass the PR number, Build URL, or Build ID to the `scripts/get_buildkite_results.py` script.

The `--jobs` flag can do glob-style filtering of jobs.

The `--download` flag will download job logs.

For quick checks with the `bk` CLI, `bk job log <job_id> --no-timestamps`
prints a job's log (it doesn't take `--build`). The output keeps a stray
`ESC _` prefix, cursor and color codes, and carriage returns; strip them
before grepping:
`sed 's/\x1b\[[0-9;]*[A-Za-z]//g; s/\x1b_//g; s/\r//g'`.

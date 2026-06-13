---
name: buildkite-get-results
description: Gets buildkite build results
---

Pass the PR number, Build URL, or Build ID to the `scripts/get_buildkite_results.py` script.
This script has been modernly updated to use the official Buildkite command line tool (`bk`).

The `--jobs` flag can do glob-style filtering of jobs.

The `--download` flag will download job logs.

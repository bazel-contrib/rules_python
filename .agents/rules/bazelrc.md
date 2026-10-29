---
trigger: glob
description: Bazel configuration (.bazelrc) rules and conventions
globs: "*.bazelrc,.bazelrc"
---

# Bazelrc Rules

* **Quote Values with Spaces**: Wrap flag values containing spaces in double
  quotes (e.g., `--build_metadata="KEY=value with spaces"`). Unquoted spaces
  cause Bazel's rc parser to treat subsequent words as build targets.
* **Document Performance Flags**: Document performance-tuning flags (e.g.,
  `--remote_cache_compression`, `--experimental_remote_cache_chunking`,
  `--rewind_lost_inputs`) with inline comments explaining their concrete
  benefit.
* **Invocation Privacy**: Keep local invocations private. Never add
  `--build_metadata=VISIBILITY=PUBLIC` to repository-level or user bazelrc
  files; configure public visibility and CI metadata only in CI.
* Use `--disk_cache=` (or `--nodisk_cache` in Bazel 10+) to disable disk
  caching; `--disk_cache=false` sets the cache directory to `./false` prior to
  Bazel 10.

---
trigger: glob
description: BazelCI presubmit.yml flag conventions
globs: ".bazelci/**"
---

# BazelCI Presubmit Config Rule

* Write `build_flags` and `test_flags` as YAML mappings with `? "--flag"`
  keys, not as lists. Don't put matrix placeholders (`${{ }}`) in those keys;
  bazelci.py doesn't expand them in mapping keys.
* To give a task the shared flags plus its own, merge the anchor instead of
  copying flags: `<<: *reusable_config_build_flags` or
  `<<: *reusable_config_test_flags`, then add the task's keys. A task's own
  `build_flags` or `test_flags` replaces the inherited mapping entirely.
* To change a merged flag, such as a tag filter, list it again: Bazel uses
  the last value.
* Pass build-configuration flags, such as `--config=ci`, to both build and
  test, so `bazel test` reuses the build's analysis cache.
* Only the root `.bazelrc` defines `--config=ci`. Tasks with a
  `working_directory` can't use it.
* When a task has several `<<:` keys, later anchors win for the same key;
  e.g. the workspace anchors replace `reusable_config`'s flags. In the list
  form, `<<: [*a, *b]`, the first anchor wins.
* After editing, run
  `bazel test --config=fast-tests //tests/bazelci:presubmit_test`. To
  review how each task's flags changed, run
  `bazel run //dev/bazelci:diff_presubmit_flags`.

# Testing & Validation Guardrails

## `--config=fast-tests` for Test Targets
* Always pass `--config=fast-tests` when running or building test targets to
  avoid running expensive, flaky integration tests.

## CRITICAL: Never use `--config=fast-tests` on Non-Test Targets
* `--config=fast-tests` sets `--build_tests_only=true`, which silently ignores
  non-test targets (such as `//docs:docs` or package libraries), resulting in 0
  targets built!

## Lockfile Testing (`MODULE.bazel.lock`)
* Changes to transitive module extension dependencies or `.bzl` files loaded by
  extensions update Bazel 9 lockfile hashes, requiring `bazel mod deps
  --lockfile_mode=update` in integration test workspaces.

## Documentation Flake Handling
* When building `//docs:docs` fails with exit code 2, treat it as a known
  Sphinx/Bazel flake and retry the build.

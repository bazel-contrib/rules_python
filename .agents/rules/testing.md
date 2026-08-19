# Testing & Validation Guardrails

## `--config=fast-tests` for Test Targets
* Always pass `--config=fast-tests` when running or building test targets to
  avoid running expensive, flaky integration tests.

## Running Integration Tests Directly
* Integration tests under `tests/integration/` are tagged
  `["integration-test", "enormous"]` and are filtered out by
  `--config=fast-tests`.
* To run a specific integration test target directly, omit
  `--config=fast-tests`: `bazel test //tests/integration:<target>`.

## CRITICAL: Never use `--config=fast-tests` on Non-Test Targets
* `--config=fast-tests` sets `--build_tests_only=true`, which silently ignores
  non-test targets (such as `//docs:docs` or package libraries), resulting in 0
  targets built!

## Lockfile Testing (`MODULE.bazel.lock`)
* Changes to transitive module extension dependencies or `.bzl` files loaded by
  extensions update Bazel 9 lockfile hashes, requiring `bazel mod deps
  --lockfile_mode=update` in integration test workspaces.
* When requirements files (e.g., in `//tools/publish` or root pip parses) are
  modified or bumped by Dependabot, update the integration lockfile by running
  `bazel mod deps --lockfile_mode=update` in `tests/integration/bzlmod_lockfile`
  and verify with
  `bazel test //tests/integration:bzlmod_lockfile_test_bazel_9.1.0`.

## Documentation Flake Handling
* When building `//docs:docs` fails with exit code 2, treat it as a known
  Sphinx/Bazel flake and retry the build.

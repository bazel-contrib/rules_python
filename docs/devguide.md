# Dev Guide

This document covers tips and guidance for working on the rules_python code
base. A primary audience for it is first time contributors.

## Running tests

Running tests is particularly easy thanks to Bazel, simply run:

```
bazel test //...
```

And it will run all the tests it can find. The first time you do this, it will
probably take long time because various dependencies will need to be downloaded
and setup. Subsequent runs will be faster, but there are many tests, and some of
them are slow. If you're working on a particular area of code, you can run just
the tests in those directories instead, which can speed up your edit-run cycle.

## Writing Tests

Most code should have tests of some sort. This helps us have confidence that
refactors didn't break anything and that releases won't have regressions.

We don't require 100% test coverage, testing certain Bazel functionality is
difficult, and some edge cases are simply too hard to test or not worth the
extra complexity. We try to judiciously decide when not having tests is a good
idea.

Tests go under `tests/`. They are loosely organized into directories for the
particular subsystem or functionality they are testing. If an existing directory
doesn't seem like a good match for the functionality being testing, then it's
fine to create a new directory.

Re-usable test helpers and support code go in `tests/support`. Tests don't need
to be perfectly factored and not every common thing a test does needs to be
factored into a more generally reusable piece. Copying and pasting is fine. It's
more important for tests to balance understandability and maintainability.

### sh_py_run_test

The {gh-path}`sh_py_run_test <tests/support/sh_py_run_test.bzl` rule is a helper to
make it easy to run a Python program with custom build settings using a shell
script to perform setup and verification. This is best to use when verifying
behavior needs certain environment variables or directory structures to
correctly and reliably verify behavior.

When adding a test, you may find the flag you need to set isn't supported by
the rule. To have it support setting a new flag, see the py_reconfig_test docs
below.

### py_reconfig_test

The `py_reconfig_test` and `py_reconfig_binary` rules are helpers for running
Python binaries and tests with custom build flags. This is best to use when
verifying behavior that requires specific flags to be set and when the program
itself can verify the desired state.

They are located in {gh-path}`tests/support/py_reconfig.bzl`

When adding a test, you may find the flag you need to set isn't supported by
the rule. To have it support setting a new flag:

* Add an attribute to the rule. It should have the same name as the flag
  it's for. It should be a string, string_list, or label attribute -- this
  allows distinguishing between if the value was specified or not.
* Modify the transition and add the flag to both the inputs and outputs
  list, then modify the transition's logic to check the attribute and set
  the flag value if the attribute is set.

### Integration tests

An integration test is one that runs a separate Bazel instance inside the test.
These tests are discouraged unless absolutely necessary because they are slow,
require much memory and CPU, and are generally harder to debug. Integration
tests are reserved for things that simple can't be tested otherwise, or for
simple high level verification tests.

Integration tests live in `tests/integration`. When possible, add to an existing
integration test.

## Updating internal dependencies

1. Modify the `./python/private/pypi/requirements.txt` file and run:
   ```
   bazel run //private:whl_library_requirements.update
   ```
1. Run the following target to update `twine` dependencies:
   ```
   bazel run //private:requirements.update
   ```
1. Bump the coverage dependencies using the script using:
   ```
   bazel run //tools/private/update_deps:update_coverage_deps <VERSION>
   # for example:
   # bazel run //tools/private/update_deps:update_coverage_deps 7.6.1
   ```

## Updating tool dependencies

It's suggested to routinely update the tool versions within our repo - some of the
tools are using requirement files compiled by `uv` and others use other means. In order
to have everything self-documented, we have a special target -
`//private:requirements.update`, which uses `rules_multirun` to run in sequence all
of the requirement updating scripts in one go. This can be done once per release as
we prepare for releases.

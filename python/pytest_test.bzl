"""
A public entrypoint for `pytest_test` rule.

Use this to create test targets using [pytest](https://pypi.org/project/pytest)
instead of having to declare the main entrypoint for your {obj}`py_test` rules.

In order to use this rule you'll have to have the following packages:
* `pytest` and [`pytest-bazel`](https://pytest-bazel.readthedocs.io/latest/) -
  used to invoke pytest. `pytest-bazel` also shards the tests and seeds the
  random number generators for `--runs_per_test`.
* `pytest-randomly` - optional, to run the tests in a random order, see
  the `pytest_randomly` argument of {obj}`pytest_test`.

:::{versionadded} 2.5.0
:::
"""

load("//python/private/pytest_test:pytest_test.bzl", _pytest_test = "pytest_test")

pytest_test = _pytest_test

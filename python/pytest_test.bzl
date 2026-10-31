"""
A public entrypoint for `pytest_test` rule.

Use this to create test targets using [pytest](https://pypi.org/project/pytest)
instead of having to declare the main entrypoint for your {obj}`py_test` rules.

In order to use this rule you'll have to have the following packages:
* `pytest` and `pytest-bazel` - used to invoke pytest.
* `pytest-randomly` - used to have consistent random number usage.
* `pytest-shard` - optional, used only if tests need to be sharded.

:::{versionadded} 2.5.0
:::
"""

load("//python/private/pytest_test:pytest_test.bzl", _pytest_test = "pytest_test")

pytest_test = _pytest_test

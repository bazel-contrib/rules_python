"""Public entrypoint for the {obj}`pytest_test` macro.

Use this to create test targets using [pytest](https://pypi.org/project/pytest)
instead of declaring a `main` entrypoint for {obj}`py_test` rules. See
{doc}`/pytest` for setup (`pytest` and `pytest-bazel >= 1.0`) and usage.

:::{versionadded} 2.5.0
:::

:::{versionchanged} VERSION_NEXT_FEATURE
`pytest-randomly` and `pytest-shard` are no longer required by default;
sharding requires `pytest-bazel >= 0.3.0`.
:::
"""

load("//python/private/pytest_test:pytest_test.bzl", _pytest_test = "pytest_test")

pytest_test = _pytest_test

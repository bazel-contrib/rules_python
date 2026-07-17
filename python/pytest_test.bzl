"""pytest_test rule re-export."""

load("//python/private/pytest_test:pytest_test.bzl", _pytest_test = "pytest_test")

pytest_test = _pytest_test

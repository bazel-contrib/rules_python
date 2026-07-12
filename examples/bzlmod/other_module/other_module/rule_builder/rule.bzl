"""A minimal custom py_binary built via the executables rule builder API.

Regression coverage for https://github.com/bazel-contrib/rules_python/pull/3919:
py_binary_rule_builder()'s implicit attr defaults (build_data_writer,
debugger_if_target_config, uncachable_version_file) previously had no
visibility outside of rules_python, so any external module (like this one)
constructing a rule via the builder failed at analysis time with a
visibility error.
"""

load("@rules_python//python/api:executables.bzl", "executables")

def _make_rule():
    builder = executables.py_binary_rule_builder()
    return builder.build()

custom_py_binary = _make_rule()

Fixed {obj}`--bootstrap_impl` resetting to `system_python` for build tools,
such as a `py_binary` run by a `genrule`, under Bazel 10. Tools no longer need
a system `python3` when `--bootstrap_impl=script` is set.

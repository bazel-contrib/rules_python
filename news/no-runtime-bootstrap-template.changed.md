(rules) When no Python runtime is available, {obj}`py_binary` and {obj}`py_test`
now fall back to rules_python's own copy of the bootstrap template instead of
`@bazel_tools//tools/python:python_bootstrap_template.txt`.

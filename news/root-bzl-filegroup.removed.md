The `//:bzl` filegroup no longer includes `.bzl` files from
`@bazel_tools//tools/python`. None of them are loaded by rules_python, and Bazel
intends to remove the unused ones.

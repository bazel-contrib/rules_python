(toolchains) {attr}`py_runtime.coverage_tool` accepts the extracted files of
the `coverage` wheel, such as `@pypi//coverage:extracted_whl_files`, so the
locked version of `coverage` can be used for coverage collection
([#3902](https://github.com/bazel-contrib/rules_python/issues/3902)).

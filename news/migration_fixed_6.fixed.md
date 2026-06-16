(pypi) Fix `importlib.metadata.files` by ensuring `RECORD` is included in
  installed wheel targets, except when built from sdist
  ([#3024](https://github.com/bazel-contrib/rules_python/issues/3024)).
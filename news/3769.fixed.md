(pypi) Assume that all of the packages are available on a particular hub if
  there is only a single PyPI compatible index to be used. This saves us an expensive
  PyPI download and supports PyPI mirror implementations that do not support the root
  index functionality. Fixes
  ([#3769](https://github.com/bazel-contrib/rules_python/pull/3769)).
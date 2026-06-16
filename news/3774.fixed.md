(system_python) Fix AttributeError exception on Debian 10 Buster
  python installations which may not set `sys._base_executable`
  ([#3774](https://github.com/bazel-contrib/rules_python/issues/3774)).
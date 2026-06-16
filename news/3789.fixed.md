(windows) Fix `py_test`/`py_binary` failure when the target name contains
  path separators; the bootstrap stub is now declared as a sibling of the
  `.exe` launcher
  ([#3789](https://github.com/bazel-contrib/rules_python/issues/3789)).
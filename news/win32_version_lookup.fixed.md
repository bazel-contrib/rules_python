Fixed a flaky error on Windows 2022 when looking up the win32 version during
site initialization by retrying the lookup
([#3721](https://github.com/bazel-contrib/rules_python/issues/3721)).

(zipapp) The self-executable {obj}`py_zipapp_binary` launcher now `exec`s the
Python interpreter, so signals sent to the PID the caller started (e.g. by a
process supervisor) reach the Python program instead of only the launcher
shell. Its temporary extraction directory is now also removed when the program
is killed with `SIGKILL`.
([#2043](https://github.com/bazel-contrib/rules_python/issues/2043))

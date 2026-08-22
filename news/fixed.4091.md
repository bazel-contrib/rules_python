(toolchain) {obj}`python_repository` now attempts to auto-detect the version
for the hermetic toolchain and exclude the `libpython` from the runtime saving
a little bit of MBs from the sandbox. Addresses
([#3534](https://github.com/bazel-contrib/rules_python/issues/3534))

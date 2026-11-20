(pypi) {obj}`pip.configure` now exposes the extras requested in the selected
`pyproject.toml` dependency groups, e.g. `requests[socks]`, as the
`@pypi//requests:[socks]` target and includes them in `@pypi//requests`, even
if the lock file does not request them
([#2786](https://github.com/bazel-contrib/rules_python/issues/2786)).

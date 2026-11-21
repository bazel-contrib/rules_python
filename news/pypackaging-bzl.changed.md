(pypi) The versions, the version specifiers, the requirements and the
environment markers are now handled by
[`pypackaging.bzl`](https://github.com/jvolkman/pypackaging.bzl), which is a
Starlark port of [`packaging`](https://github.com/pypa/packaging). This means
that invalid input, which was silently accepted before, is now an error and
that the environment markers are evaluated like `packaging` does it:
`platform_version` is compared as a string, the local version segments are
not ignored in `==` comparisons and the non-standard `not` operator is no
longer accepted. `WORKSPACE` users get `pypackaging.bzl` from `py_repositories`.

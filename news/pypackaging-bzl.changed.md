(pypi) The requirements and the environment markers are now handled by
[`pypackaging.bzl`](https://github.com/jvolkman/pypackaging.bzl), which is a
Starlark port of [`packaging`](https://github.com/pypa/packaging). This means
that invalid input, which was silently accepted before, is now an error,
including the `Requires-Dist` lines in the `METADATA` of the wheels, and that
the environment markers are evaluated like `packaging` does it:
`platform_release` is compared as a version and `platform_version` as a
string, the ordered comparisons of the strings and of the invalid versions
are no longer lexicographic (`<` and `>` are always false, `<=` and `>=` are
the same as `==`), the local version segments are not ignored in `==`
comparisons and the non-standard `not` operator is no longer accepted.
`WORKSPACE` users get `pypackaging.bzl` from {obj}`py_repositories`.

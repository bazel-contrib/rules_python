(pypi) The requirements are now parsed by
[`pypackaging.bzl`](https://github.com/jvolkman/pypackaging.bzl), which is a
Starlark port of [`packaging`](https://github.com/pypa/packaging). This means
that invalid input, which was silently accepted before, is now an error.
`WORKSPACE` users get `pypackaging.bzl` from `py_repositories`.

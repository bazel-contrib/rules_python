(pypi) Invalid versions, version specifiers, PEP 508 requirements and
environment markers now fail instead of being silently accepted, as they are
now parsed by [`pypackaging.bzl`](https://github.com/jvolkman/pypackaging.bzl)
(a Starlark port of [`packaging`](https://github.com/pypa/packaging)). The
markers are evaluated like `packaging` does it, e.g. `platform_release` is
compared as a version and the ordered comparisons of strings are always false.
`WORKSPACE` users get `pypackaging.bzl` from {obj}`py_repositories`.

(pypi) Invalid PEP 508 requirements now fail instead of being silently accepted,
as requirements are now parsed by
[`pypackaging.bzl`](https://github.com/jvolkman/pypackaging.bzl) (a Starlark
port of [`packaging`](https://github.com/pypa/packaging)). `WORKSPACE` users
get `pypackaging.bzl` from {obj}`py_repositories`.

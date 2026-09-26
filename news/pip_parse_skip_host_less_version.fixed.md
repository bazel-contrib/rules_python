(pypi) A `pip.parse` for a Python version that has no interpreter for the host
platform is now skipped, like a version missing from the minor mapping, instead
of failing the whole `pip` extension. A dependency that lists, say, Python 3.9
no longer breaks every other hub on hosts that have no CPython 3.9 build, such
as Windows on ARM64.

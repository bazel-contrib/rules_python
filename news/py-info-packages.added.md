(rules) Added {obj}`PyInfo.packages` with the normalized names of the PyPI
packages in the transitive closure of a target, e.g. so that a `py_test` can
tell whether it already depends on `coverage`.

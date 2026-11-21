(pypi) The versions in the environment markers are compared as described in
the [version specifiers spec](https://packaging.python.org/en/latest/specifications/version-specifiers/)
when they have a different number of release segments, pre-, post- or
dev-release segments or local versions, e.g. `python_full_version == "3.13.0.*"`
now matches `3.13` and `python_full_version >= "3"` no longer matches
`3.0rc1`.

(pypi) The `MODULE.bazel.lock` facts now store only the wheels that a configured
{obj}`pip.default` platform can select for one of the requested Python versions.
This makes the lockfile smaller. If you change the platforms or the Python
versions, the extension reads the index again.

(pypi) The `MODULE.bazel.lock` facts now store all sdists, but only the wheels
that a configured {obj}`pip.default` platform can select for one of the
requested Python versions. This makes the lockfile smaller. The first run after
the upgrade fetches the index again, so update the lockfile if you use
`--lockfile_mode=error`. After that, the extension fetches the index again only
if you change the platforms or the major or minor Python versions.

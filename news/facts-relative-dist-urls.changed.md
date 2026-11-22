(pypi) The `MODULE.bazel.lock` facts now store the distribution URLs of each
package relative to the longest directory that the URLs share. This makes the
lockfile smaller. The first run after the upgrade fetches the index again, so
update the lockfile if you use `--lockfile_mode=error`.

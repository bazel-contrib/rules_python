(toolchains) {obj}`python.single_version_override` without `urls` no longer
resets the `strip_prefix` of the existing archives, which broke the
freethreaded toolchains that use the `full` archives.

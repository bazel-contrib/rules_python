(bzl_library) Migrated `bzl_library` targets to be managed by Gazelle using the
`bazel-skylib` Gazelle plugin. Public targets have been renamed to match their
file names (without the `_bzl` suffix), and deprecated aliases have been
created for backwards compatibility.

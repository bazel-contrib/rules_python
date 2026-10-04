(zipapp) Shared libraries that a {obj}`py_zipapp_binary` reaches through
Bazel's `_solib` symlinks are stored as files again, instead of as symlinks to
absolute paths in the build machine's output base that dangle wherever the
zipapp runs.

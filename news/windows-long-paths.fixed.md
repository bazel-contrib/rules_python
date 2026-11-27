(binaries/tests) (Windows) {obj}`py_binary` and {obj}`py_test` work with
runfiles paths of 260 characters or more when `LongPathsEnabled` is off, which
is the default. Before, the venv created at runtime without the privilege to
create symlinks could be missing files, and the runfiles directory wasn't found,
so imports failed.

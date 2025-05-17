"""Utilities to get where we should write namespace pkg paths."""

load("@bazel_skylib//rules:write_file.bzl", "write_file")

_ext = struct(
    py = ".py",
    pyi = ".pyi",
    pyd = ".pyd",
    so = ".so",
    pyc = ".pyc",
)

_INIT_CONTENTS = """\
# __path__ manipulation added by bazel-contrib/rules_python to support namespace pkgs.
__path__ = __import__('pkgutil').extend_path(__path__, __name__)
""".split("\n")

def _add_all(dirname, dirs):
    dir_path = "."
    for dir_name in dirname.split("/"):
        dir_path = "{}/{}".format(dir_path, dir_name)
        dirs[dir_path[2:]] = None

def get_files(*, srcs, ignored_dirnames = [], root = None):
    """Get the list of filenames to write the namespace pkg files.

    Args:
        srcs: {type}`src` a list of files to be passed to {bzl:obj}`py_library`
            as `srcs` and `data`. This is usually a result of a {obj}`glob`.
        ignored_dirnames: {type}`str` a list of patterns to ignore.
        root: {type}`str` the prefix to use as the root.

    Returns:
        {type}`src` a list of paths to write the namespace pkg `__init__.py` file.
    """
    dirs = {}
    ignored = {i: None for i in ignored_dirnames}

    if root:
        _add_all(root, ignored)

    for file in srcs:
        dirname, _, filename = file.rpartition("/")

        if filename == "__init__.py":
            ignored[dirname] = None
            dirname, _, _ = dirname.rpartition("/")
        elif filename.endswith(_ext.py):
            pass
        elif filename.endswith(_ext.pyc):
            pass
        elif filename.endswith(_ext.pyd):
            pass
        elif filename.endswith(_ext.pyi):
            pass
        elif filename.endswith(_ext.so):
            pass
        else:
            continue

        if dirname in dirs or not dirname:
            continue

        _add_all(dirname, dirs)

    return sorted([d for d in dirs if d not in ignored])

def create_inits(**kwargs):
    """Create init files and return the list to be included `py_library` srcs.

    Args:
        **kwargs: passed to {obj}`get_files`.

    Returns:
        {type}`list[str]` to be included as part of `py_library`.
    """
    srcs = []
    for out in get_files(**kwargs):
        src = "{}/__init__.py".format(out)
        srcs.append(srcs)

        write_file(
            name = "_gen_{}_namespace".format(out),
            out = src,
            content = _INIT_CONTENTS,
            **kwargs
        )

    return srcs

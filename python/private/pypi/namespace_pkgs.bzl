"""Utilities to get where we should write namespace pkg paths."""

EXTS = [
    ".py",
    ".pyd",
    ".so",
    ".pyc",
]

def _get_files(files, ignored_dirnames = []):
    dirs = {}
    ignored = {i: None for i in ignored_dirnames}
    for file in files:
        dirname, _, filename = file.rpartition("/")

        if filename == "__init__.py":
            ignored[dirname] = None
            dirname, _, _ = dirname.rpartition("/")
        elif filename.endswith(EXTS[0]):
            pass
        elif filename.endswith(EXTS[1]):
            pass
        elif filename.endswith(EXTS[2]):
            pass
        elif filename.endswith(EXTS[3]):
            pass
        else:
            continue

        if dirname in dirs or not dirname:
            continue

        dir_path = "."
        for dir_name in dirname.split("/"):
            dir_path = "{}/{}".format(dir_path, dir_name)
            dirs[dir_path[2:]] = None

    return sorted([d for d in dirs if d not in ignored])

namespace_pkgs = struct(
    get_files = _get_files,
)

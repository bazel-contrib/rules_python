"""Generated wheel file list and wheel_glob wrapper."""

load("//python/private/pypi:py_wheel_extract_files.bzl", _wheel_glob = "wheel_glob")  # buildifier: disable=bzl-visibility

FILES = [
    "site-packages/bad_top_mod.py",
    "site-packages/demo_pkg-1.2.3.dist-info/METADATA",
    "site-packages/demo_pkg/__init__.py",
    "site-packages/demo_pkg/include/demo_header.h",
    "site-packages/demo_pkg/lib/libdemo.so",
]

def wheel_glob(
        include,
        exclude = [],
        exclude_directories = 1,
        allow_empty = True,
        *,
        wheel_library = Label("//tests/pypi/py_wheel_library/spoke_pkg:_wheel_install"),
        is_executable = False):
    """Glob over wheel files in this repository."""
    return _wheel_glob(
        include = include,
        exclude = exclude,
        exclude_directories = exclude_directories,
        allow_empty = allow_empty,
        files = FILES,
        wheel_library = wheel_library,
        is_executable = is_executable,
    )

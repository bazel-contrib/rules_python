"""Public entry point for `py_dist_info`.

Use {obj}`py_dist_info` to generate `.dist-info` metadata (`METADATA` and
`entry_points.txt`) in runfiles so that Python's `importlib.metadata` can
discover package versions and entry points at runtime, or to provide reusable
metadata for {obj}`py_wheel`.

:::{versionadded} VERSION_NEXT_FEATURE
:::
"""

load(
    "//python/private:py_dist_info.bzl",
    _PyDistInfo = "PyDistInfo",
    _py_dist_info = "py_dist_info",
)

PyDistInfo = _PyDistInfo
py_dist_info = _py_dist_info

(rules) Added {obj}`py_dist_info` in `@rules_python//python:py_dist_info.bzl`
to generate `.dist-info` metadata (`METADATA` and `entry_points.txt`) in
runfiles so `importlib.metadata` can discover package versions and entry points
at runtime.

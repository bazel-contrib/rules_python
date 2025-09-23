"""Public API for py_extension."""

load(
    "//python/private/cc:py_extension_macro.bzl",
    _py_extension = "py_extension",
)

py_extension = _py_extension

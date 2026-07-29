"""Public API for py_extension.

:::{include} /_includes/experimental_api.md
:::
"""

load(
    "//python/private/cc:py_extension_macro.bzl",
    _py_extension = "py_extension",
)

py_extension = _py_extension

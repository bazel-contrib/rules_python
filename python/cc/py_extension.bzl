"""Rules for creating Python C extension modules.

This module provides `py_extension` for building Python C extension modules
that can be imported by Python targets (`py_binary`, `py_test`, `py_library`).
It manages dynamic linking, symbol exports (`PyInit_*`), platform-specific link
flags, and target dependencies cleanly.

See the [Python C API documentation](https://docs.python.org/3/c-api/index.html)
for information on writing C extension modules.

:::{include} /_includes/experimental_api.md
:::

:::{versionadded} 2.3.0
:::
"""

load(
    "//python/private/cc:py_extension_macro.bzl",
    _py_extension = "py_extension",
)

py_extension = _py_extension

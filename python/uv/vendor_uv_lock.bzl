"""Vendor a `uv.lock` file as a `.bzl` file, e.g. to use it in WORKSPACE macros.

:::{versionadded} VERSION_NEXT_FEATURE
:::
"""

load("//python/uv/private:vendor_uv_lock.bzl", _vendor_uv_lock = "vendor_uv_lock")

vendor_uv_lock = _vendor_uv_lock

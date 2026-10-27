"""Repository rules and macros to set up `uv` in a WORKSPACE file."""

load("//python/uv/private:uv_register_toolchains.bzl", _uv_register_toolchains = "uv_register_toolchains")
load("//python/uv/private:uv_toolchains_manifest.bzl", _uv_toolchains_manifest = "uv_toolchains_manifest")

uv_register_toolchains = _uv_register_toolchains
uv_toolchains_manifest = _uv_toolchains_manifest

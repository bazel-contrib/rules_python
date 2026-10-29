"""Local HTTP and caller-provided wheel fixtures."""

load("@rules_python//python/private/pypi:whl_library.bzl", "whl_library")  # buildifier: disable=bzl-visibility

_FILENAME = "storage_pkg-1.0-py3-none-any.whl"

def _patches(filename):
    return {
        Label("//:modify_pkg.patch"): json.encode({
            "patch_strip": 0,
            "whls": [filename],
        }),
    }

def _wheels_impl(mrctx):
    common = {
        "envsubst": ["WHEEL_TEST_ADDRESS"],
        "filename": _FILENAME,
        "requirement": "storage-pkg",
        "sha256": mrctx.read(Label("//:wheel.sha256")).strip(),
        "urls": ["http://${WHEEL_TEST_ADDRESS}/" + _FILENAME],
    }
    whl_library(name = "plain", **common)
    whl_library(name = "patched", whl_patches = _patches(_FILENAME), **common)
    whl_library(name = "nonmatching", whl_patches = _patches("other.whl"), **common)
    whl_library(
        name = "provided",
        requirement = "storage-pkg",
        whl_file = Label("//:" + _FILENAME),
    )
    whl_library(
        name = "provided_patched",
        requirement = "storage-pkg",
        whl_file = Label("//:" + _FILENAME),
        whl_patches = _patches(_FILENAME),
    )

wheels = module_extension(implementation = _wheels_impl)

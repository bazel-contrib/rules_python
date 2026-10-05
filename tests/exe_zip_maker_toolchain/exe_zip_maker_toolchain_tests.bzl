"""Tests that the dev-only exe_zip_maker toolchain is used."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", rt_util = "util")
load("//python:py_binary.bzl", "py_binary")
load("//python/zipapp:py_zipapp_binary.bzl", "py_zipapp_binary")
load("//tests/support:support.bzl", "SUPPORTS_BZLMOD")

_tests = []

# When developing rules_python (bzlmod), MODULE.bazel registers a toolchain
# that points to the Rust implementation, gated behind a flag. These tests
# verify the rules pick it up when enabled, and use the Python fallback
# otherwise.
#
# The dev toolchain is only registered under bzlmod; in WORKSPACE mode,
# rules_rust is a stub and the Python fallback is used, so skip there.
_RUST_EXE_ZIP_MAKER_SUFFIX = "crates/exe_zip_maker/exe_zip_maker"
_PYTHON_EXE_ZIP_MAKER_SUFFIX = "tools/zipapp/exe_zip_maker_.py"
_USE_RUST_FLAG = str(Label("//dev/dev_only_toolchains:use_rust_exe_zip_maker"))

def _define_py_zipapp_subject(name):
    rt_util.helper_target(
        py_binary,
        name = name + "_bin",
        srcs = ["main.py"],
        main = "main.py",
    )
    rt_util.helper_target(
        py_zipapp_binary,
        name = name + "_subject",
        binary = name + "_bin",
    )

def _test_py_zipapp_uses_toolchain_exe_zip_maker(name):
    _define_py_zipapp_subject(name)
    analysis_test(
        name = name,
        impl = _test_py_zipapp_uses_toolchain_exe_zip_maker_impl,
        target = name + "_subject",
        config_settings = {
            _USE_RUST_FLAG: "yes",
        },
        attr_values = {"target_compatible_with": SUPPORTS_BZLMOD},
    )

def _test_py_zipapp_uses_toolchain_exe_zip_maker_impl(env, target):
    action = env.expect.that_target(target).action_named(
        "PyZipAppCreateExecutableZip",
    )
    action.argv().contains_predicate(
        matching.str_endswith(_RUST_EXE_ZIP_MAKER_SUFFIX),
    )

_tests.append(_test_py_zipapp_uses_toolchain_exe_zip_maker)

def _test_py_zipapp_flag_disabled_uses_python_exe_zip_maker(name):
    _define_py_zipapp_subject(name)
    analysis_test(
        name = name,
        impl = _test_py_zipapp_flag_disabled_uses_python_exe_zip_maker_impl,
        target = name + "_subject",
        config_settings = {
            _USE_RUST_FLAG: "no",
        },
        attr_values = {"target_compatible_with": SUPPORTS_BZLMOD},
    )

def _test_py_zipapp_flag_disabled_uses_python_exe_zip_maker_impl(env, target):
    action = env.expect.that_target(target).action_named(
        "PyZipAppCreateExecutableZip",
    )
    action.argv().contains_predicate(
        matching.str_endswith(_PYTHON_EXE_ZIP_MAKER_SUFFIX),
    )

_tests.append(_test_py_zipapp_flag_disabled_uses_python_exe_zip_maker)

def exe_zip_maker_toolchain_test_suite(name):
    test_suite(
        name = name,
        tests = _tests,
    )

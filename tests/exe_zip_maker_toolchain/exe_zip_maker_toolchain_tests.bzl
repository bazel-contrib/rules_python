"""Tests for the exe_zip_maker toolchain configuration and registration."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:unit_test.bzl", "unit_test")
load("@rules_testing//lib:util.bzl", rt_util = "util")
load("//python:py_binary.bzl", "py_binary")
load("//python/private/toolchains:repo.bzl", "configure_tool_toolchains")  # buildifier: disable=bzl-visibility
load("//python/private/zipapp:py_exe_zip_maker_toolchain.bzl", "py_exe_zip_maker_toolchain")  # buildifier: disable=bzl-visibility
load("//python/zipapp:py_zipapp_binary.bzl", "py_zipapp_binary")
load("//tests/support:support.bzl", "NOT_WINDOWS", "SUPPORTS_BZLMOD")
load("//tests/support/mocks:mocks.bzl", "mocks")

_tests = []

# Under bzlmod, MODULE.bazel registers @rules_python_tools//toolchains:all,
# which points to the Rust implementation (from source in git, or prebuilt in
# release archives) when use_rust_exe_zip_maker is "auto" (in dev mode) or
# "yes", and falls back to the Python implementation when "no".
#
# In WORKSPACE mode, rules_rust is a stub and the Python fallback is used, so
# skip there.
#
# On Windows, py_zipapp uses the Bazel launcher instead of a self-executable
# zip, so the exe_zip_maker toolchain is never used; skip there too.
_COMPATIBLE_WITH = SUPPORTS_BZLMOD + NOT_WINDOWS
_RUST_EXE_ZIP_MAKER_SUFFIX = "crates/exe_zip_maker/exe_zip_maker"
_PYTHON_EXE_ZIP_MAKER_SUFFIX = "tools/zipapp/exe_zip_maker_.py"
_USE_RUST_FLAG = str(Label("//python/private/toolchains:use_rust_exe_zip_maker"))

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

def _test_py_zipapp_default_uses_toolchain_exe_zip_maker(name):
    _define_py_zipapp_subject(name)
    analysis_test(
        name = name,
        impl = _test_py_zipapp_uses_toolchain_exe_zip_maker_impl,
        target = name + "_subject",
        attr_values = {"target_compatible_with": _COMPATIBLE_WITH},
    )

_tests.append(_test_py_zipapp_default_uses_toolchain_exe_zip_maker)

def _test_py_zipapp_uses_toolchain_exe_zip_maker(name):
    _define_py_zipapp_subject(name)
    analysis_test(
        name = name,
        impl = _test_py_zipapp_uses_toolchain_exe_zip_maker_impl,
        target = name + "_subject",
        config_settings = {
            _USE_RUST_FLAG: "yes",
        },
        attr_values = {"target_compatible_with": _COMPATIBLE_WITH},
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
        attr_values = {"target_compatible_with": _COMPATIBLE_WITH},
    )

def _test_py_zipapp_flag_disabled_uses_python_exe_zip_maker_impl(env, target):
    action = env.expect.that_target(target).action_named(
        "PyZipAppCreateExecutableZip",
    )
    action.argv().contains_predicate(
        matching.str_endswith(_PYTHON_EXE_ZIP_MAKER_SUFFIX),
    )

_tests.append(_test_py_zipapp_flag_disabled_uses_python_exe_zip_maker)

def _test_prebuilt_file_toolchain_target(name):
    rt_util.helper_target(
        py_exe_zip_maker_toolchain,
        name = name + "_subject",
        exe_zip_maker = "main.py",
    )
    analysis_test(
        name = name,
        impl = _test_prebuilt_file_toolchain_target_impl,
        target = name + "_subject",
    )

def _test_prebuilt_file_toolchain_target_impl(env, target):
    tc_info = target[platform_common.ToolchainInfo]
    exe = tc_info.exe_zip_maker[DefaultInfo].files_to_run.executable
    env.expect.that_file(exe).short_path_equals(
        "tests/exe_zip_maker_toolchain/main.py",
    )

_tests.append(_test_prebuilt_file_toolchain_target)

def _test_configure_tool_toolchains_from_source(name):
    unit_test(
        name = name,
        impl = _test_configure_tool_toolchains_from_source_impl,
    )

def _test_configure_tool_toolchains_from_source_impl(env):
    http_file = mocks.repo()
    toolchain_repo = mocks.repo()
    tools_toolchains_repo = mocks.repo()
    configure_tool_toolchains(
        http_file = http_file.rule,
        prebuilt_exe_zip_maker_toolchain_impl_repo = toolchain_repo.rule,
        tools_toolchains_repo = tools_toolchains_repo.rule,
        artifacts_manifest_json = "\n",
    )
    env.expect.that_collection(http_file.calls).contains_exactly([])
    env.expect.that_collection(toolchain_repo.calls).contains_exactly([])
    env.expect.that_collection(tools_toolchains_repo.calls).contains_exactly([
        {
            "exec_compatible_with": {"0": []},
            "name": "rules_python_tools",
            "toolchain_impls": [
                "@rules_python//python/private/toolchains/from_source:exe_zip_maker",
            ],
            "toolchain_names": [
                "exe_zip_maker_from_source",
            ],
        },
    ])

_tests.append(_test_configure_tool_toolchains_from_source)

def _test_configure_tool_toolchains_prebuilt(name):
    unit_test(
        name = name,
        impl = _test_configure_tool_toolchains_prebuilt_impl,
    )

def _test_configure_tool_toolchains_prebuilt_impl(env):
    manifest_json = json.encode({
        "artifacts": {
            "exe_zip_maker": [
                {
                    "exec_compatible_with": [
                        "@platforms//cpu:aarch64",
                        "@platforms//os:macos",
                    ],
                    "name": "exe_zip_maker_aarch64_apple_darwin",
                    "sha256": "deadbeef1",
                    "urls": ["https://example.com/exe_zip_maker-aarch64-apple-darwin"],
                },
                {
                    "exec_compatible_with": [
                        "@platforms//cpu:x86_64",
                        "@platforms//os:windows",
                    ],
                    "name": "exe_zip_maker_x86_64_pc_windows_msvc",
                    "sha256": "deadbeef2",
                    "urls": ["https://example.com/exe_zip_maker-x86_64-pc-windows-msvc.exe"],
                },
            ],
        },
    })
    http_file = mocks.repo()
    toolchain_repo = mocks.repo()
    tools_toolchains_repo = mocks.repo()
    configure_tool_toolchains(
        http_file = http_file.rule,
        prebuilt_exe_zip_maker_toolchain_impl_repo = toolchain_repo.rule,
        tools_toolchains_repo = tools_toolchains_repo.rule,
        artifacts_manifest_json = manifest_json,
    )
    env.expect.that_collection(http_file.calls).contains_exactly([
        {
            "executable": True,
            "name": "rules_python_exe_zip_maker_aarch64_apple_darwin_file",
            "sha256": "deadbeef1",
            "urls": ["https://example.com/exe_zip_maker-aarch64-apple-darwin"],
        },
        {
            "executable": True,
            "name": "rules_python_exe_zip_maker_x86_64_pc_windows_msvc_file",
            "sha256": "deadbeef2",
            "urls": ["https://example.com/exe_zip_maker-x86_64-pc-windows-msvc.exe"],
        },
    ])
    env.expect.that_collection(toolchain_repo.calls).contains_exactly([
        {
            "exe_zip_maker": "@rules_python_exe_zip_maker_aarch64_apple_darwin_file//file",
            "name": "rules_python_exe_zip_maker_aarch64_apple_darwin_toolchain",
        },
        {
            "exe_zip_maker": "@rules_python_exe_zip_maker_x86_64_pc_windows_msvc_file//file",
            "name": "rules_python_exe_zip_maker_x86_64_pc_windows_msvc_toolchain",
        },
    ])
    env.expect.that_collection(tools_toolchains_repo.calls).contains_exactly([
        {
            "exec_compatible_with": {
                "0": [
                    "@platforms//cpu:aarch64",
                    "@platforms//os:macos",
                ],
                "1": [
                    "@platforms//cpu:x86_64",
                    "@platforms//os:windows",
                ],
            },
            "name": "rules_python_tools",
            "toolchain_impls": [
                "@rules_python_exe_zip_maker_aarch64_apple_darwin_toolchain//:toolchain",
                "@rules_python_exe_zip_maker_x86_64_pc_windows_msvc_toolchain//:toolchain",
            ],
            "toolchain_names": [
                "exe_zip_maker_aarch64_apple_darwin",
                "exe_zip_maker_x86_64_pc_windows_msvc",
            ],
        },
    ])

_tests.append(_test_configure_tool_toolchains_prebuilt)

def exe_zip_maker_toolchain_test_suite(name):
    test_suite(
        name = name,
        tests = _tests,
    )

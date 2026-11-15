"""Tests for the shrubbery toolchain configuration and registration."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:unit_test.bzl", "unit_test")
load("@rules_testing//lib:util.bzl", rt_util = "util")
load("//python:packaging.bzl", "py_wheel")
load("//python:py_binary.bzl", "py_binary")
load("//python/private/toolchains:repo.bzl", "configure_tool_toolchains")  # buildifier: disable=bzl-visibility
load("//python/private/toolchains:shrubbery_toolchain.bzl", "shrubbery_toolchain")  # buildifier: disable=bzl-visibility
load("//python/zipapp:py_zipapp_binary.bzl", "py_zipapp_binary")
load("//tests/support:support.bzl", "NOT_WINDOWS", "SUPPORTS_BZLMOD")
load("//tests/support/mocks:mocks.bzl", "mocks")

_tests = []

# Under bzlmod, MODULE.bazel registers @rules_python_tools//toolchains:all,
# which points to the unified Rust shrubbery binary (from source in git, or
# prebuilt in release archives) when need_shrubbery is "auto" (in dev mode) or
# "yes", and falls back to the built-in Python/script tools when "no".
#
# In WORKSPACE mode, rules_rust is a stub and the Python fallback is used, so
# skip there.
#
# On Windows, py_zipapp uses the Bazel launcher instead of a self-executable
# zip (so PyZipAppCreateExecutableZip is not created), so skip py_zipapp action
# tests on Windows.
_ZIPAPP_COMPATIBLE_WITH = SUPPORTS_BZLMOD + NOT_WINDOWS
_SHRUBBERY_SUFFIX = "crates/shrubbery/shrubbery"
_PYTHON_EXE_ZIP_MAKER_SUFFIX = "tools/zipapp/exe_zip_maker_.py"
_PYTHON_WHEELMAKER_SUFFIX = "tools/wheelmaker"
_PYTHON_ZIP_MAIN_MAKER_SUFFIX = "tools/zipapp/zip_main_maker_.py"
_PYTHON_ZIPPER_SUFFIX = "tools/zipapp/zipper_.py"
_NEED_SHRUBBERY_FLAG = str(Label("//python/private/toolchains:need_shrubbery"))

def _endswith_exe(suffix):
    return matching.custom(
        "<endswith '{}[.exe]'>".format(suffix),
        lambda v: v.removesuffix(".exe").endswith(suffix),
    )

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

def _test_py_zipapp_default_uses_toolchain_shrubbery(name):
    _define_py_zipapp_subject(name)
    analysis_test(
        name = name,
        impl = _test_py_zipapp_uses_toolchain_shrubbery_impl,
        target = name + "_subject",
        attr_values = {"target_compatible_with": _ZIPAPP_COMPATIBLE_WITH},
    )

_tests.append(_test_py_zipapp_default_uses_toolchain_shrubbery)

def _test_py_zipapp_uses_toolchain_shrubbery(name):
    _define_py_zipapp_subject(name)
    analysis_test(
        name = name,
        impl = _test_py_zipapp_uses_toolchain_shrubbery_impl,
        target = name + "_subject",
        config_settings = {
            _NEED_SHRUBBERY_FLAG: "yes",
        },
        attr_values = {"target_compatible_with": _ZIPAPP_COMPATIBLE_WITH},
    )

def _test_py_zipapp_uses_toolchain_shrubbery_impl(env, target):
    for mnemonic, subcommand in [
        # keep-sorted start
        ("PyZipAppCreateExecutableZip", "exe_zip_maker"),
        ("PyZipAppCreateMainPy", "zip_main_maker"),
        ("PyZipAppCreateZip", "zipper"),
        # keep-sorted end
    ]:
        action = env.expect.that_target(target).action_named(mnemonic)
        action.argv().contains_predicate(
            matching.str_endswith(_SHRUBBERY_SUFFIX),
        )
        action.argv().contains(subcommand)

_tests.append(_test_py_zipapp_uses_toolchain_shrubbery)

def _test_py_zipapp_flag_disabled_uses_python_fallbacks(name):
    _define_py_zipapp_subject(name)
    analysis_test(
        name = name,
        impl = _test_py_zipapp_flag_disabled_uses_python_fallbacks_impl,
        target = name + "_subject",
        config_settings = {
            _NEED_SHRUBBERY_FLAG: "no",
        },
        attr_values = {"target_compatible_with": _ZIPAPP_COMPATIBLE_WITH},
    )

def _test_py_zipapp_flag_disabled_uses_python_fallbacks_impl(env, target):
    for mnemonic, py_suffix in [
        # keep-sorted start
        ("PyZipAppCreateExecutableZip", _PYTHON_EXE_ZIP_MAKER_SUFFIX),
        ("PyZipAppCreateMainPy", _PYTHON_ZIP_MAIN_MAKER_SUFFIX),
        ("PyZipAppCreateZip", _PYTHON_ZIPPER_SUFFIX),
        # keep-sorted end
    ]:
        action = env.expect.that_target(target).action_named(mnemonic)
        action.argv().contains_predicate(
            matching.str_endswith(py_suffix),
        )

_tests.append(_test_py_zipapp_flag_disabled_uses_python_fallbacks)

def _define_py_wheel_subject(name):
    rt_util.helper_target(
        py_wheel,
        name = name + "_subject",
        distribution = "mydist",
        version = "1.0.0",
    )

def _test_py_wheel_default_uses_toolchain_shrubbery(name):
    _define_py_wheel_subject(name)
    analysis_test(
        name = name,
        impl = _test_py_wheel_uses_toolchain_shrubbery_impl,
        target = name + "_subject",
        attr_values = {"target_compatible_with": SUPPORTS_BZLMOD},
    )

_tests.append(_test_py_wheel_default_uses_toolchain_shrubbery)

def _test_py_wheel_uses_toolchain_shrubbery(name):
    _define_py_wheel_subject(name)
    analysis_test(
        name = name,
        impl = _test_py_wheel_uses_toolchain_shrubbery_impl,
        target = name + "_subject",
        config_settings = {
            _NEED_SHRUBBERY_FLAG: "yes",
        },
        attr_values = {"target_compatible_with": SUPPORTS_BZLMOD},
    )

def _test_py_wheel_uses_toolchain_shrubbery_impl(env, target):
    action = env.expect.that_target(target).action_named("PyWheel")
    action.argv().contains_predicate(_endswith_exe(_SHRUBBERY_SUFFIX))
    action.argv().contains("wheelmaker")

_tests.append(_test_py_wheel_uses_toolchain_shrubbery)

def _test_py_wheel_flag_disabled_uses_python_wheelmaker(name):
    _define_py_wheel_subject(name)
    analysis_test(
        name = name,
        impl = _test_py_wheel_flag_disabled_uses_python_wheelmaker_impl,
        target = name + "_subject",
        config_settings = {
            _NEED_SHRUBBERY_FLAG: "no",
        },
        attr_values = {"target_compatible_with": SUPPORTS_BZLMOD},
    )

def _test_py_wheel_flag_disabled_uses_python_wheelmaker_impl(env, target):
    action = env.expect.that_target(target).action_named("PyWheel")
    action.argv().contains_predicate(_endswith_exe(_PYTHON_WHEELMAKER_SUFFIX))

_tests.append(_test_py_wheel_flag_disabled_uses_python_wheelmaker)

def _test_prebuilt_file_toolchain_target(name):
    rt_util.helper_target(
        shrubbery_toolchain,
        name = name + "_subject",
        shrubbery = "main.py",
    )
    analysis_test(
        name = name,
        impl = _test_prebuilt_file_toolchain_target_impl,
        target = name + "_subject",
    )

def _test_prebuilt_file_toolchain_target_impl(env, target):
    tc_info = target[platform_common.ToolchainInfo]
    exe = tc_info.shrubbery[DefaultInfo].files_to_run.executable
    env.expect.that_file(exe).short_path_equals(
        "tests/shrubbery_toolchain/main.py",
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
        prebuilt_shrubbery_toolchain_impl_repo = toolchain_repo.rule,
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
                "@rules_python//python/private/toolchains/from_source:shrubbery",
            ],
            "toolchain_names": [
                "shrubbery_from_source",
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
            "shrubbery": [
                {
                    "exec_compatible_with": [
                        "@platforms//cpu:aarch64",
                        "@platforms//os:macos",
                    ],
                    "name": "shrubbery_aarch64_apple_darwin",
                    "sha256": "deadbeef1",
                    "urls": ["https://example.com/shrubbery-aarch64-apple-darwin"],
                },
                {
                    "exec_compatible_with": [
                        "@platforms//cpu:x86_64",
                        "@platforms//os:windows",
                    ],
                    "name": "shrubbery_x86_64_pc_windows_msvc",
                    "sha256": "deadbeef2",
                    "urls": ["https://example.com/shrubbery-x86_64-pc-windows-msvc.exe"],
                },
            ],
        },
    })
    http_file = mocks.repo()
    toolchain_repo = mocks.repo()
    tools_toolchains_repo = mocks.repo()
    configure_tool_toolchains(
        http_file = http_file.rule,
        prebuilt_shrubbery_toolchain_impl_repo = toolchain_repo.rule,
        tools_toolchains_repo = tools_toolchains_repo.rule,
        artifacts_manifest_json = manifest_json,
    )
    env.expect.that_collection(http_file.calls).contains_exactly([
        {
            "executable": True,
            "name": "rules_python_shrubbery_aarch64_apple_darwin_file",
            "sha256": "deadbeef1",
            "urls": ["https://example.com/shrubbery-aarch64-apple-darwin"],
        },
        {
            "executable": True,
            "name": "rules_python_shrubbery_x86_64_pc_windows_msvc_file",
            "sha256": "deadbeef2",
            "urls": ["https://example.com/shrubbery-x86_64-pc-windows-msvc.exe"],
        },
    ])
    env.expect.that_collection(toolchain_repo.calls).contains_exactly([
        {
            "name": "rules_python_shrubbery_aarch64_apple_darwin_toolchain",
            "shrubbery": "@rules_python_shrubbery_aarch64_apple_darwin_file//file",
        },
        {
            "name": "rules_python_shrubbery_x86_64_pc_windows_msvc_toolchain",
            "shrubbery": "@rules_python_shrubbery_x86_64_pc_windows_msvc_file//file",
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
                "@rules_python_shrubbery_aarch64_apple_darwin_toolchain//:toolchain",
                "@rules_python_shrubbery_x86_64_pc_windows_msvc_toolchain//:toolchain",
            ],
            "toolchain_names": [
                "shrubbery_aarch64_apple_darwin",
                "shrubbery_x86_64_pc_windows_msvc",
            ],
        },
    ])

_tests.append(_test_configure_tool_toolchains_prebuilt)

def shrubbery_toolchain_test_suite(name):
    test_suite(
        name = name,
        tests = _tests,
    )

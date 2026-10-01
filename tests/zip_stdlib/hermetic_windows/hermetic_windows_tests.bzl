"""Tests for hermetic runtime setup for Windows with zip_stdlib."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load(
    "//python/private:py_runtime_info.bzl",
    "PyRuntimeInfo",
)  # buildifier: disable=bzl-visibility
load(
    "//tests/support/platforms:platforms.bzl",
    "platform_targets",
)  # buildifier: disable=bzl-visibility

_tests = []

def _test_windows_py_runtime_contains_zip_stdlib(name):
    analysis_test(
        name = name,
        target = ":py3_runtime",
        impl = _test_windows_py_runtime_contains_zip_stdlib_impl,
        config_settings = {
            "//command_line_option:platforms": [
                platform_targets.WINDOWS_X86_64,
            ],
        },
    )

def _test_windows_py_runtime_contains_zip_stdlib_impl(env, target):
    info = target[PyRuntimeInfo]
    env.expect.that_collection(
        info.files.to_list(),
    ).contains_predicate(
        matching.file_basename_equals("python311.zip"),
    )
    env.expect.that_collection(
        info.venv_bin_files,
    ).contains_predicate(
        matching.file_basename_equals("python311.zip"),
    )
    env.expect.that_bool(info.zip_stdlib != None).equals(True)
    env.expect.that_str(info.zip_stdlib.basename).equals("python311.zip")

_tests.append(_test_windows_py_runtime_contains_zip_stdlib)

_PY_FREETHREADED = str(Label("//python/config_settings:py_freethreaded"))

def _test_windows_py_runtime_contains_zip_stdlib_freethreaded(name):
    analysis_test(
        name = name,
        target = ":py3_runtime",
        impl = _test_windows_py_runtime_contains_zip_stdlib_freethreaded_impl,
        config_settings = {
            "//command_line_option:platforms": [
                platform_targets.WINDOWS_X86_64,
            ],
            _PY_FREETHREADED: "yes",
        },
    )

def _test_windows_py_runtime_contains_zip_stdlib_freethreaded_impl(env, target):
    info = target[PyRuntimeInfo]
    env.expect.that_collection(
        info.files.to_list(),
    ).contains_predicate(
        matching.file_basename_equals("python311t.zip"),
    )
    env.expect.that_collection(
        info.venv_bin_files,
    ).contains_predicate(
        matching.file_basename_equals("python311t.zip"),
    )
    env.expect.that_bool(info.zip_stdlib != None).equals(True)
    env.expect.that_str(info.zip_stdlib.basename).equals("python311t.zip")

_tests.append(_test_windows_py_runtime_contains_zip_stdlib_freethreaded)

def _test_windows_zip_stdlib_target(name):
    analysis_test(
        name = name,
        target = ":zip_stdlib",
        impl = _test_windows_zip_stdlib_target_impl,
        config_settings = {
            "//command_line_option:platforms": [
                platform_targets.WINDOWS_X86_64,
            ],
        },
    )

def _test_windows_zip_stdlib_target_impl(env, target):
    action = env.expect.that_target(target).action_named("ZipStdlib")
    action.mnemonic().equals("ZipStdlib")
    env.expect.that_target(target).default_outputs().contains_predicate(
        matching.file_basename_equals("python311.zip"),
    )

_tests.append(_test_windows_zip_stdlib_target)

_ZIP_STDLIB = str(Label("//python/config_settings:zip_stdlib"))

def _test_windows_py_runtime_does_not_contain_zip_stdlib_when_flag_disabled(
        name):
    analysis_test(
        name = name,
        target = ":py3_runtime",
        impl = (
            _test_windows_py_runtime_flag_disabled_impl
        ),
        config_settings = {
            "//command_line_option:platforms": [
                platform_targets.WINDOWS_X86_64,
            ],
            _ZIP_STDLIB: "no",
        },
    )

def _test_windows_py_runtime_flag_disabled_impl(
        env,
        target):
    info = target[PyRuntimeInfo]
    env.expect.that_collection(
        info.files.to_list(),
    ).not_contains_predicate(
        matching.file_basename_equals("python311.zip"),
    )
    env.expect.that_collection(
        info.venv_bin_files,
    ).not_contains_predicate(
        matching.file_basename_equals("python311.zip"),
    )
    env.expect.that_bool(info.zip_stdlib == None).equals(True)

_tests.append(
    _test_windows_py_runtime_does_not_contain_zip_stdlib_when_flag_disabled,
)

def hermetic_windows_test_suite(name):
    test_suite(
        name = name,
        tests = _tests,
    )

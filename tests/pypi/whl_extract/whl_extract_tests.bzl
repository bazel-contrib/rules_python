"""Tests for whl_extract and gen_wheel_record."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:util.bzl", rt_util = "util")
load(
    "//python/private/pypi:gen_wheel_record.bzl",  # buildifier: disable=bzl-visibility
    "gen_wheel_record",
)
load(
    "//tests/support/platforms:platforms.bzl",  # buildifier: disable=bzl-visibility
    "platform_targets",
)

_tests = []

def _test_gen_wheel_record(name):
    rt_util.helper_target(
        native.genrule,
        name = name + "_src",
        outs = [name + "_orig/alpha-1.0.dist-info/RECORD"],
        cmd = "echo 'alpha-1.0.data/scripts/foo.sh' > $@",
    )
    rt_util.helper_target(
        gen_wheel_record,
        name = name + "_subject",
        srcs = [":" + name + "_src"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_gen_wheel_record_impl,
    )

_tests.append(_test_gen_wheel_record)

def _test_gen_wheel_record_impl(env, target):
    files = target[DefaultInfo].files.to_list()
    env.expect.that_collection(files).has_size(1)
    env.expect.that_str(files[0].short_path).contains(
        "site-packages/alpha-1.0.dist-info/RECORD",
    )

def _test_gen_wheel_record_windows(name):
    rt_util.helper_target(
        native.genrule,
        name = name + "_src",
        outs = [name + "_orig/beta-1.0.dist-info/RECORD"],
        cmd = "echo 'beta-1.0.data/scripts/foo.sh' > $@",
    )
    rt_util.helper_target(
        gen_wheel_record,
        name = name + "_subject",
        srcs = [":" + name + "_src"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:platforms": [
                platform_targets.WINDOWS_X86_64,
            ],
        },
        impl = _test_gen_wheel_record_windows_impl,
    )

_tests.append(_test_gen_wheel_record_windows)

def _test_gen_wheel_record_windows_impl(env, target):
    files = target[DefaultInfo].files.to_list()
    env.expect.that_collection(files).has_size(1)
    env.expect.that_str(files[0].short_path).contains(
        "site-packages/beta-1.0.dist-info/RECORD",
    )

def _test_gen_wheel_record_multiple_srcs(name):
    rt_util.helper_target(
        native.genrule,
        name = name + "_src1",
        outs = [name + "_orig1/gamma-1.0.dist-info/RECORD"],
        cmd = "echo 'gamma-1.0.data/scripts/foo.sh' > $@",
    )
    rt_util.helper_target(
        native.genrule,
        name = name + "_src2",
        outs = [name + "_orig2/delta-2.0.dist-info/RECORD"],
        cmd = "echo 'delta-2.0.data/scripts/bar.sh' > $@",
    )
    rt_util.helper_target(
        gen_wheel_record,
        name = name + "_subject",
        srcs = [":" + name + "_src1", ":" + name + "_src2"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_gen_wheel_record_multiple_srcs_impl,
    )

_tests.append(_test_gen_wheel_record_multiple_srcs)

def _test_gen_wheel_record_multiple_srcs_impl(env, target):
    files = target[DefaultInfo].files.to_list()
    env.expect.that_collection(files).has_size(2)
    paths = [f.short_path for f in files]
    env.expect.that_bool(
        any(["site-packages/gamma-1.0.dist-info/RECORD" in p for p in paths]),
    ).equals(True)
    env.expect.that_bool(
        any(["site-packages/delta-2.0.dist-info/RECORD" in p for p in paths]),
    ).equals(True)

def _test_gen_wheel_record_rewritten_scripts(name):
    rt_util.helper_target(
        native.genrule,
        name = name + "_src",
        outs = [name + "_orig/epsilon-1.0.dist-info/RECORD"],
        cmd = "echo 'epsilon-1.0.data/scripts/foo.sh' > $@",
    )
    rt_util.helper_target(
        gen_wheel_record,
        name = name + "_subject",
        srcs = [":" + name + "_src"],
        rewritten_scripts = ["foo", "my tool"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_gen_wheel_record_rewritten_scripts_impl,
    )

_tests.append(_test_gen_wheel_record_rewritten_scripts)

def _test_gen_wheel_record_rewritten_scripts_impl(env, target):
    files = target[DefaultInfo].files.to_list()
    env.expect.that_collection(files).has_size(1)
    action = env.expect.that_target(target).action_generating(files[0].short_path)
    action.argv().contains("foo")
    action.argv().contains("my tool")

def whl_extract_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, tests = _tests)

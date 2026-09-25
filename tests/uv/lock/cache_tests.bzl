"""Cache policy tests for build actions and runnable lock targets."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/uv:lock.bzl", "lock")
load("//tests/support/platforms:platforms.bzl", "platform_targets")

def _cache_tests(name, is_windows, extension):
    config_settings = {
        "//command_line_option:platforms": [
            platform_targets.WINDOWS_X86_64 if is_windows else platform_targets.LINUX_X86_64,
        ],
    }
    for no_cache in [False, True]:
        subject = name + ("_no_cache" if no_cache else "_default")
        lock(
            name = subject,
            srcs = ["testdata/pyproject.toml"],
            args = ["--no-cache"] if no_cache else [],
            out = subject + extension,
        )
        analysis_test(
            name = subject + "_build_test",
            impl = _test_windows_build_impl if is_windows else _test_build_impl,
            target = subject,
            config_settings = config_settings,
        )
        analysis_test(
            name = subject + "_run_test",
            impl = _test_no_cache_run_impl if no_cache else _test_run_impl,
            target = subject + ".run",
            config_settings = config_settings,
        )
    native.test_suite(
        name = name,
        tests = [
            name + mode + kind
            for mode in ["_default", "_no_cache"]
            for kind in ["_build_test", "_run_test"]
        ],
    )

def _test_build_impl(env, target):
    output = target[DefaultInfo].files.to_list()[0]
    env.expect.that_target(target).action_generating(output.short_path).argv().contains("--no-cache")

def _test_windows_build_impl(env, target):
    env.expect.that_target(target).action_generating(
        "{package}/{name}_lock.bat",
    ).content().contains("--no-cache")

def _run_script(env, target):
    executable = target[DefaultInfo].files_to_run.executable
    return env.expect.that_target(target).action_generating(executable.short_path).content()

def _test_run_impl(env, target):
    _run_script(env, target).split("--no-cache").has_size(1)

def _test_no_cache_run_impl(env, target):
    _run_script(env, target).contains("--no-cache")

def _test_requirements_cache(name):
    _cache_tests(name, is_windows = False, extension = ".txt")

def _test_uv_lock_cache(name):
    _cache_tests(name, is_windows = False, extension = ".lock")

def _test_windows_requirements_cache(name):
    _cache_tests(name, is_windows = True, extension = ".txt")

def _test_windows_uv_lock_cache(name):
    _cache_tests(name, is_windows = True, extension = ".lock")

def cache_test_suite(name):
    """Check cache defaults and explicit `--no-cache` for both lock formats."""
    test_suite(
        name = name,
        tests = [
            _test_requirements_cache,
            _test_uv_lock_cache,
            _test_windows_requirements_cache,
            _test_windows_uv_lock_cache,
        ],
    )

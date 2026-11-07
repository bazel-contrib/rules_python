"Tests for creating the select_whl target platform for python toolchains."

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private/pypi:python_toolchain_platform.bzl", "python_toolchain_platform")  # buildifier: disable=bzl-visibility

_tests = []

def _test_whl_platform_tags(env):
    for platform_name, want in {
        "aarch64-apple-darwin": ["any", "macosx_*_universal2", "macosx_*_arm64"],
        "aarch64-pc-windows-msvc": ["any", "win_arm64"],
        "aarch64-unknown-linux-gnu": ["any", "manylinux_*_aarch64"],
        "arm64e-apple-darwin": ["any"],
        "armv7-unknown-linux-gnu": ["any", "manylinux_*_armv7l"],
        "i386-unknown-linux-gnu": ["any", "manylinux_*_i686"],
        "i686-pc-windows-msvc": ["any", "win32"],
        "ppc64le-unknown-linux-gnu": ["any", "manylinux_*_ppc64le"],
        "riscv64-unknown-linux-gnu": ["any", "manylinux_*_riscv64"],
        "s390x-unknown-linux-gnu": ["any", "manylinux_*_s390x"],
        "x86_64-apple-darwin": ["any", "macosx_*_universal2", "macosx_*_x86_64"],
        "x86_64-pc-windows-msvc": ["any", "win_amd64"],
        "x86_64-unknown-linux-gnu": ["any", "manylinux_*_x86_64"],
        "x86_64-unknown-linux-gnu-freethreaded": ["any", "manylinux_*_x86_64"],
        "x86_64-unknown-linux-musl": ["any", "musllinux_*_x86_64"],
    }.items():
        got = python_toolchain_platform(
            python_version = "3.13.1",
            platform_name = platform_name,
        )
        env.expect.where(
            platform_name = platform_name,
        ).that_collection(got.whl_platform_tags).contains_exactly(want).in_order()

_tests.append(_test_whl_platform_tags)

def _test_whl_abi_tags(env):
    got = python_toolchain_platform(
        python_version = "3.13.1",
        platform_name = "x86_64-unknown-linux-gnu",
    )
    env.expect.that_collection(got.whl_abi_tags).contains_exactly([
        "none",
        "abi3",
        "cp313",
    ]).in_order()

    got = python_toolchain_platform(
        python_version = "3.13",
        platform_name = "aarch64-apple-darwin-freethreaded",
    )
    env.expect.that_collection(got.whl_abi_tags).contains_exactly([
        "none",
        "cp313t",
    ]).in_order()

_tests.append(_test_whl_abi_tags)

def _test_env(env):
    got = python_toolchain_platform(
        python_version = "3.15.0",
        platform_name = "aarch64-unknown-linux-gnu",
    )
    env.expect.that_str(got.env["python_version"]).equals("3.15")
    env.expect.that_str(got.env["python_full_version"]).equals("3.15.0")
    env.expect.that_str(got.env["implementation_name"]).equals("cpython")
    env.expect.that_str(got.env["sys_platform"]).equals("linux")
    env.expect.that_str(got.env["platform_machine"]).equals("aarch64")

    got = python_toolchain_platform(
        python_version = "3.13",
        platform_name = "x86_64-apple-darwin",
    )
    env.expect.that_str(got.env["python_full_version"]).equals("3.13.0")
    env.expect.that_str(got.env["sys_platform"]).equals("darwin")
    env.expect.that_str(got.env["platform_machine"]).equals("x86_64")

_tests.append(_test_env)

def python_toolchain_platform_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite.
    """
    test_suite(name = name, basic_tests = _tests)

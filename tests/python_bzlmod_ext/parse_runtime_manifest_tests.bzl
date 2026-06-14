"""Tests for manifest parsing Starlark functions."""

load("@bazel_skylib//lib:structs.bzl", "structs")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:util.bzl", rt_util = "util")
load("//python/private:pbs_manifest.bzl", "parse_filename", "parse_runtime_manifest")  # buildifier: disable=bzl-visibility

_tests = []

def _test_parse_filename_baseline(name):
    """Sets up the baseline filename parsing test.

    Args:
      name: The name of the test.
    """
    rt_util.helper_target(
        native.filegroup,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_parse_filename_baseline_impl,
    )

def _test_parse_filename_baseline_impl(env, target):
    _ = target  # @unused

    # 1. Baseline
    parsed1 = parse_filename("cpython-3.11.15+20260414-x86_64-unknown-linux-gnu-install_only.tar.gz")
    env.expect.that_dict(parsed1).contains_exactly({
        "arch": "x86_64",
        "archive_flavor": "install_only",
        "build_flavor": "",
        "build_version": "20260414",
        "freethreaded": False,
        "libc": "gnu",
        "location": "cpython-3.11.15+20260414-x86_64-unknown-linux-gnu-install_only.tar.gz",
        "microarch": "",
        "os": "linux",
        "python_version": "3.11.15",
        "vendor": "unknown",
    })

    # 2. Microarch
    parsed2 = parse_filename("cpython-3.10.20+20260414-x86_64_v2-unknown-linux-musl-lto-full.tar.zst")
    env.expect.that_dict(parsed2).contains_exactly({
        "arch": "x86_64",
        "archive_flavor": "full",
        "build_flavor": "lto",
        "build_version": "20260414",
        "freethreaded": False,
        "libc": "musl",
        "location": "cpython-3.10.20+20260414-x86_64_v2-unknown-linux-musl-lto-full.tar.zst",
        "microarch": "v2",
        "os": "linux",
        "python_version": "3.10.20",
        "vendor": "unknown",
    })

    # 3. Freethreaded
    parsed3 = parse_filename("cpython-3.13.13+20260414-aarch64-apple-darwin-freethreaded+pgo+lto-full.tar.zst")
    env.expect.that_dict(parsed3).contains_exactly({
        "arch": "aarch64",
        "archive_flavor": "full",
        "build_flavor": "pgo+lto",
        "build_version": "20260414",
        "freethreaded": True,
        "libc": "",
        "location": "cpython-3.13.13+20260414-aarch64-apple-darwin-freethreaded+pgo+lto-full.tar.zst",
        "microarch": "",
        "os": "darwin",
        "python_version": "3.13.13",
        "vendor": "apple",
    })

    # 4. Invalid
    parsed4 = parse_filename("invalid-filename.tar.gz")
    env.expect.that_bool(parsed4 == None).equals(True)

    # 5. Full URL (should return the original URL as location)
    parsed5 = parse_filename("https://github.com/astral-sh/python-build-standalone/releases/download/20260414/cpython-3.11.15+20260414-x86_64-unknown-linux-gnu-install_only.tar.gz")
    env.expect.that_dict(parsed5).contains_exactly({
        "arch": "x86_64",
        "archive_flavor": "install_only",
        "build_flavor": "",
        "build_version": "20260414",
        "freethreaded": False,
        "libc": "gnu",
        "location": "https://github.com/astral-sh/python-build-standalone/releases/download/20260414/cpython-3.11.15+20260414-x86_64-unknown-linux-gnu-install_only.tar.gz",
        "microarch": "",
        "os": "linux",
        "python_version": "3.11.15",
        "vendor": "unknown",
    })

_tests.append(_test_parse_filename_baseline)

def _test_parse_runtime_manifest(name):
    """Sets up the manifest file parsing test.

    Args:
      name: The name of the test.
    """
    rt_util.helper_target(
        native.filegroup,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_parse_runtime_manifest_impl,
    )

def _test_parse_runtime_manifest_impl(env, target):
    _ = target  # @unused
    content = """
8b14030dd3af9ea7f7c51b4c90feb04afd8a8f45435727e67b875270bd08f3bc   cpython-3.11.15+20260414-x86_64-unknown-linux-gnu-install_only.tar.gz
a57ffd435652092d16b30e783f9826c55e9c64b0f0a72cbae0a9f39e663137fb       cpython-3.11.15+20260414-aarch64-apple-darwin-install_only.tar.gz
ce18fdfd47c66830a40ea9b9e314a14b1636bbfd684501bc5ca1fc6d55a7933f  https://example.com/cpython-3.10.20+20260414-x86_64_v2-unknown-linux-musl-lto-full.tar.zst
1111111111111111111111111111111111111111111111111111111111111111  cpython-3.13.13+20260414-aarch64-apple-darwin-freethreaded+pgo+lto-full.tar.zst
"""
    parsed = parse_runtime_manifest(content)
    env.expect.that_collection(parsed).has_size(4)

    env.expect.that_dict(structs.to_dict(parsed[0])).contains_exactly({
        "arch": "x86_64",
        "archive_flavor": "install_only",
        "build_flavor": "",
        "build_version": "20260414",
        "freethreaded": False,
        "libc": "gnu",
        "location": "cpython-3.11.15+20260414-x86_64-unknown-linux-gnu-install_only.tar.gz",
        "microarch": "",
        "os": "linux",
        "python_version": "3.11.15",
        "sha256": "8b14030dd3af9ea7f7c51b4c90feb04afd8a8f45435727e67b875270bd08f3bc",
        "vendor": "unknown",
    })

    env.expect.that_dict(structs.to_dict(parsed[2])).contains_exactly({
        "arch": "x86_64",
        "archive_flavor": "full",
        "build_flavor": "lto",
        "build_version": "20260414",
        "freethreaded": False,
        "libc": "musl",
        "location": "https://example.com/cpython-3.10.20+20260414-x86_64_v2-unknown-linux-musl-lto-full.tar.zst",
        "microarch": "v2",
        "os": "linux",
        "python_version": "3.10.20",
        "sha256": "ce18fdfd47c66830a40ea9b9e314a14b1636bbfd684501bc5ca1fc6d55a7933f",
        "vendor": "unknown",
    })

    env.expect.that_dict(structs.to_dict(parsed[3])).contains_exactly({
        "arch": "aarch64",
        "archive_flavor": "full",
        "build_flavor": "pgo+lto",
        "build_version": "20260414",
        "freethreaded": True,
        "libc": "",
        "location": "cpython-3.13.13+20260414-aarch64-apple-darwin-freethreaded+pgo+lto-full.tar.zst",
        "microarch": "",
        "os": "darwin",
        "python_version": "3.13.13",
        "sha256": "1111111111111111111111111111111111111111111111111111111111111111",
        "vendor": "apple",
    })

_tests.append(_test_parse_runtime_manifest)

def parse_runtime_manifest_test_suite(name):
    """Defines the test suite for manifest parsing.

    Args:
      name: The name of the test suite.
    """
    test_suite(
        name = name,
        tests = _tests,
    )

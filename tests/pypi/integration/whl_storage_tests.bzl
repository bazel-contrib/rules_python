"""Check archive storage and runtime dependencies for a downloaded wheel."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//tests/support:support.bzl", "SUPPORTS_BZLMOD")

def _test_downloaded_archive(name):
    analysis_test(
        name = name,
        target = "@rules_python_publish_deps//packaging:whl",
        impl = _test_downloaded_archive_impl,
        # WORKSPACE resolves this fixture through pip_archive, which retains
        # its existing archive layout. Only bzlmod supplies a known wheel URL.
        attr_values = {"target_compatible_with": SUPPORTS_BZLMOD},
    )

def _test_downloaded_archive_impl(env, target):
    files = target[DefaultInfo].files.to_list()
    env.expect.that_collection(files).has_size(1)
    for file in files:
        env.expect.that_bool(file.basename.endswith(".whl")).equals(True)
        env.expect.that_bool(file.owner.workspace_name.endswith("_whl")).equals(True)

def _test_runtime_excludes_archive(name):
    analysis_test(
        name = name,
        target = "@rules_python_publish_deps//packaging:pkg",
        impl = _test_runtime_excludes_archive_impl,
    )

def _test_runtime_excludes_archive_impl(env, target):
    files = target[DefaultInfo].default_runfiles.files.to_list()
    env.expect.that_bool(bool(files)).equals(True)
    env.expect.that_collection([
        file.short_path
        for file in files
        if file.extension == "whl"
    ]).contains_exactly([])

def whl_storage_test_suite(name):
    """Create tests for separate archive storage and wheel target compatibility."""
    test_suite(
        name = name,
        tests = [
            _test_downloaded_archive,
            _test_runtime_excludes_archive,
        ],
    )

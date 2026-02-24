""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private/pypi:version_from_filename.bzl", "version_from_filename")  # buildifier: disable=bzl-visibility

_tests = []

def _test_wheel_version_extraction(env):
    # Case 1: wheel
    env.expect.that_str(version_from_filename("foo-1.2.3-py3-none-any.whl")).equals("1.2.3")

_tests.append(_test_wheel_version_extraction)

def _test_sdist_version_extraction(env):
    # Case 1: Standard sdist
    env.expect.that_str(version_from_filename("foo-1.2.3.tar.gz")).equals("1.2.3")

    # Case 2: PEP 625 - Project name has underscores (normalized from dashes)
    # If the package is 'my-pkg', the sdist might be 'my_pkg-1.0.0.tar.gz'
    env.expect.that_str(version_from_filename("my_pkg-1.0.0.tar.gz")).equals("1.0.0")

    # Case 3: Project name has multiple underscores
    env.expect.that_str(version_from_filename("very_long_project_name-0.5.0.zip")).equals("0.5.0")

    # Case 4: Legacy sdist with hyphens in name
    # Note: Modern tools normalize this, but we should support the hyphen split
    env.expect.that_str(version_from_filename("complex-name-1.2.3.tar.gz")).equals("1.2.3")

    # Case 5: Version contains an underscore (e.g. local versions)
    env.expect.that_str(version_from_filename("pkg-1.2.3_post1.tar.gz")).equals("1.2.3_post1")

    # Case 6: custom compression
    env.expect.that_str(version_from_filename("pkg-1.2.3_post1.tar.xz")).equals("1.2.3_post1")

_tests.append(_test_sdist_version_extraction)

def _test_sdist_version_extraction_fail(env):
    failures = []

    # Case 1: 7z
    env.expect.that_str(version_from_filename("foo-1.2.3.7z")).equals(None)
    env.expect.that_str(version_from_filename("foo-1.2.3.7z", _fail = failures.append)).equals(None)
    env.expect.that_collection(failures).contains_exactly(["Unsupported sdist extension: foo-1.2.3.7z"])

    # Case 2: egg
    failures.clear()
    env.expect.that_str(version_from_filename("foo-1.2.3-py3.egg", _fail = failures.append)).equals(None)
    env.expect.that_collection(failures).contains_exactly(["Unsupported sdist extension: foo-1.2.3-py3.egg"])

_tests.append(_test_sdist_version_extraction_fail)

def version_from_filename_test_suite(name):
    test_suite(
        name = name,
        basic_tests = _tests,
    )

""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private/pypi:argparse.bzl", "argparse")  # buildifier: disable=bzl-visibility

_tests = []

def _test_index_url(env):
    env.expect.that_str(argparse.index_url([], "default")).equals("default")
    env.expect.that_str(argparse.index_url([], None)).equals(None)

    env.expect.that_str(argparse.index_url(["-i", "https://example.com/simple"], "default")).equals("https://example.com/simple")
    env.expect.that_str(argparse.index_url(["--index-url", "https://example.com/simple"], "default")).equals("https://example.com/simple")
    env.expect.that_str(argparse.index_url(["--index-url=https://example.com/simple"], "default")).equals("https://example.com/simple")

    env.expect.that_str(argparse.index_url(["--extra-index-url", "https://extra.com", "-i", "https://index.com"], "default")).equals("https://index.com")

_tests.append(_test_index_url)

def _test_extra_index_url(env):
    env.expect.that_collection(argparse.extra_index_url([], ["default"])).contains_exactly(["default"])
    env.expect.that_collection(argparse.extra_index_url([], None)).contains_exactly([])

    env.expect.that_collection(argparse.extra_index_url(["--extra-index-url", "https://extra.com/simple"], [])).contains_exactly(["https://extra.com/simple"])
    env.expect.that_collection(argparse.extra_index_url(["--extra-index-url=https://extra.com/simple"], [])).contains_exactly(["https://extra.com/simple"])

    env.expect.that_collection(argparse.extra_index_url(["--extra-index-url", "https://first.com", "--extra-index-url", "https://second.com"], [])).contains_exactly(["https://first.com", "https://second.com"])

_tests.append(_test_extra_index_url)

def _test_platform(env):
    env.expect.that_collection(argparse.platform([], ["default"])).contains_exactly(["default"])
    env.expect.that_collection(argparse.platform([], None)).contains_exactly([])

    env.expect.that_collection(argparse.platform(["--platform", "manylinux_2_17_x86_64"], [])).contains_exactly(["manylinux_2_17_x86_64"])
    env.expect.that_collection(argparse.platform(["--platform=manylinux_2_17_x86_64"], [])).contains_exactly(["manylinux_2_17_x86_64"])

    env.expect.that_collection(argparse.platform(["--platform", "macosx_10_9_x86_64", "--platform", "linux_x86_64"], [])).contains_exactly(["macosx_10_9_x86_64", "linux_x86_64"])

_tests.append(_test_platform)

def argparse_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)

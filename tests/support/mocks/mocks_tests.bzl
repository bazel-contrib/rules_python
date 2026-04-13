"""Tests for mocks.bzl"""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//tests/support/mocks:mocks.bzl", "mocks")

_tests = []

def _test_path(env):
    p1 = mocks.path("a/b/c", mock_files = {"a/b/c": "data"})
    env.expect.that_bool(p1.exists).equals(True)
    env.expect.that_str(p1.basename).equals("c")
    env.expect.that_str(p1.dirname).equals("a/b")
    env.expect.that_str(p1._path).equals("a/b/c")

    p2 = mocks.path("d/e/f", mock_files = {})
    env.expect.that_bool(p2.exists).equals(False)

_tests.append(_test_path)

def _test_file(env):
    # Default main repo
    f1 = mocks.file("a/b.txt", is_source = True)
    env.expect.that_str(f1.path).equals("a/b.txt")
    env.expect.that_str(f1.short_path).equals("a/b.txt")
    env.expect.that_str(f1.basename).equals("b.txt")
    env.expect.that_str(f1.dirname).equals("a")
    env.expect.that_str(f1.extension).equals("txt")
    env.expect.that_bool(f1.is_source).equals(True)
    env.expect.that_str(str(f1.owner)).equals(str(Label("//:mock")))

    # External repo
    f2 = mocks.file("a/b.txt", is_source = True, owner = "@foo//:mock")
    env.expect.that_str(f2.path).equals("external/foo/a/b.txt")
    env.expect.that_str(f2.short_path).equals("../foo/a/b.txt")

    # External repo generated file
    f3 = mocks.file("a/b.txt", is_source = False, owner = "@foo//:mock")
    env.expect.that_str(f3.path).equals(
        "bazel-out/k9-deadbeef/bin/external/foo/a/b.txt",
    )
    env.expect.that_str(f3.short_path).equals("../foo/a/b.txt")

_tests.append(_test_file)

def _test_mctx(env):
    mctx = mocks.mctx(
        environ = {"FOO": "bar"},
        mock_files = {"file.txt": "content"},
        mock_downloads = {"http://example.com": "downloaded"},
        os_name = "windows",
        arch_name = "x86_64",
    )
    env.expect.that_str(mctx.getenv("FOO")).equals("bar")
    env.expect.that_str(mctx.read(mocks.path("file.txt"))).equals("content")
    env.expect.that_str(mctx.os.name).equals("windows")
    env.expect.that_str(mctx.os.arch).equals("x86_64")

    # Test download
    res = mctx.download("http://example.com", "out.txt")
    env.expect.that_bool(res.success).equals(True)
    env.expect.that_str(mctx.read(mocks.path("out.txt"))).equals("downloaded")

    # Test report progress
    mctx.report_progress("doing something")
    env.expect.that_collection(mctx.report_progress_calls).contains_exactly([
        "doing something",
    ])

_tests.append(_test_mctx)

def _test_rctx(env):
    rctx = mocks.rctx(
        environ = {"FOO": "bar"},
        mock_files = {"file.txt": "content"},
        mock_which = {"mycmd": "path/to/mycmd"},
    )
    env.expect.that_str(rctx.os_environ["FOO"]).equals("bar")
    env.expect.that_str(rctx.read(mocks.path("file.txt"))).equals("content")

    # Test which
    w = rctx.which("mycmd")
    env.expect.that_str(w._path).equals("path/to/mycmd")
    env.expect.that_bool(rctx.which("not_found") == None).equals(True)

    # Test file writing
    rctx.file("new.txt", "new content")
    env.expect.that_str(rctx.read(mocks.path("new.txt"))).equals("new content")

    # Test template
    rctx.file("template.txt", "Hello {name}")
    rctx.template("rendered.txt", "template.txt", {"{name}": "World"})
    env.expect.that_str(rctx.read(mocks.path("rendered.txt"))).equals(
        "Hello World",
    )

    # Test symlink reading
    rctx.symlink("rendered.txt", "link.txt")
    env.expect.that_str(rctx.read(mocks.path("link.txt"))).equals("Hello World")

_tests.append(_test_rctx)

def _test_glob(env):
    g = mocks.glob()
    g.results.append(["a.txt", "b.txt"])
    res = g.glob(["*.txt"], exclude = ["c.txt"])
    env.expect.that_collection(res).contains_exactly(["a.txt", "b.txt"])
    env.expect.that_collection(g.calls).has_size(1)
    env.expect.that_collection(g.calls[0].glob[0]).contains_exactly(["*.txt"])
    env.expect.that_collection(g.calls[0].kwargs["exclude"]).contains_exactly([
        "c.txt",
    ])

_tests.append(_test_glob)

def _test_module_and_tags(env):
    mod = mocks.module(
        "my_mod",
        is_root = True,
        my_tag = [mocks.tag(attr1 = "val1")],
    )
    env.expect.that_str(mod.name).equals("my_mod")
    env.expect.that_bool(mod.is_root).equals(True)
    env.expect.that_str(mod.tags.my_tag[0].attr1).equals("val1")

_tests.append(_test_module_and_tags)

def _test_select(env):
    res = mocks.select({"//conditions:default": "val"})
    env.expect.that_dict(res).contains_exactly({"//conditions:default": "val"})

_tests.append(_test_select)

def mocks_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)

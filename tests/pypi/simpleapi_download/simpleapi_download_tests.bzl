# Copyright 2024 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private/pypi:pypi_cache.bzl", "pypi_cache")  # buildifier: disable=bzl-visibility
load("//python/private/pypi:simpleapi_download.bzl", "simpleapi_download")  # buildifier: disable=bzl-visibility
load("//tests/support/mocks:mocks.bzl", "mocks")

_tests = []

def _test_simple(env):
    calls = []

    def read_simpleapi(ctx, url, versions, attr, cache, get_auth, block, parse_index):
        if parse_index:
            return struct(
                success = True,
                output = {
                    "bar": "/bar/",
                    "baz": "/baz/",
                } if "main" in url else {
                    "foo": "/foo/",
                },
            )

        _ = ctx, attr, cache, get_auth, versions  # buildifier: disable=unused-variable
        env.expect.that_bool(block).equals(False)
        calls.append(url)
        return struct(
            output = struct(
                sdists = {"deadbeef": url.strip("/").split("/")[-1]},
                whls = {"deadb33f": url.strip("/").split("/")[-1]},
                sha256s_by_version = {"fizz": url.strip("/").split("/")[-1]},
            ),
            success = True,
        )

    contents = simpleapi_download(
        ctx = mocks.mctx(),
        attr = struct(
            index_url_overrides = {},
            index_url = "https://main.com",
            extra_index_urls = ["https://extra.com"],
            sources = {"bar": None, "baz": None, "foo": None},
            envsubst = [],
        ),
        cache = pypi_cache(),
        parallel_download = True,
        read_simpleapi = read_simpleapi,
    )

    env.expect.that_collection(calls).contains_exactly([
        "https://extra.com/foo/",
        "https://main.com/bar/",
        "https://main.com/baz/",
    ])
    env.expect.that_dict(contents).contains_exactly({
        "bar": struct(
            index_url = "https://main.com/bar/",
            sdists = {"deadbeef": "bar"},
            sha256s_by_version = {"fizz": "bar"},
            whls = {"deadb33f": "bar"},
        ),
        "baz": struct(
            index_url = "https://main.com/baz/",
            sdists = {"deadbeef": "baz"},
            sha256s_by_version = {"fizz": "baz"},
            whls = {"deadb33f": "baz"},
        ),
        "foo": struct(
            index_url = "https://extra.com/foo/",
            sdists = {"deadbeef": "foo"},
            sha256s_by_version = {"fizz": "foo"},
            whls = {"deadb33f": "foo"},
        ),
    })

_tests.append(_test_simple)

def _test_index_overrides(env):
    calls = []
    fails = []

    def read_simpleapi(ctx, *, url, versions, attr, cache, get_auth, block, parse_index):
        if parse_index:
            return struct(
                success = True,
                output = {
                    # normalized
                    "ba_z": "/ba-z/",
                    "bar": "/bar/",
                    "foo": "/foo-should-fail/",
                } if "main" in url else {
                    "foo": "/foo/",
                },
            )

        _ = ctx, attr, cache, get_auth, versions  # buildifier: disable=unused-variable
        env.expect.that_bool(block).equals(False)
        calls.append(url)
        return struct(
            output = struct(
                sdists = {"deadbeef": url.strip("/").split("/")[-1]},
                whls = {"deadb33f": url.strip("/").split("/")[-1]},
                sha256s_by_version = {"fizz": url.strip("/").split("/")[-1]},
            ),
            success = True,
        )

    contents = simpleapi_download(
        ctx = mocks.mctx(),
        attr = struct(
            index_url_overrides = {
                "foo": "https://extra.com",
            },
            index_url = "https://main.com",
            extra_index_urls = [],
            sources = {"ba_z": None, "bar": None, "foo": None},
            envsubst = [],
        ),
        cache = pypi_cache(),
        parallel_download = True,
        read_simpleapi = read_simpleapi,
        _fail = fails.append,
    )

    env.expect.that_collection(fails).contains_exactly([])
    env.expect.that_collection(calls).contains_exactly([
        "https://main.com/bar/",
        "https://main.com/ba-z/",
        "https://extra.com/foo/",
    ])
    env.expect.that_dict(contents).contains_exactly({
        "ba_z": struct(
            index_url = "https://main.com/ba-z/",
            sdists = {"deadbeef": "ba-z"},
            sha256s_by_version = {"fizz": "ba-z"},
            whls = {"deadb33f": "ba-z"},
        ),
        "bar": struct(
            index_url = "https://main.com/bar/",
            sdists = {"deadbeef": "bar"},
            sha256s_by_version = {"fizz": "bar"},
            whls = {"deadb33f": "bar"},
        ),
        "foo": struct(
            index_url = "https://extra.com/foo/",
            sdists = {"deadbeef": "foo"},
            sha256s_by_version = {"fizz": "foo"},
            whls = {"deadb33f": "foo"},
        ),
    })

_tests.append(_test_index_overrides)

def _test_download_url(env):
    downloads = {}
    reads = [
        # The first read is the index which seeds the downloads later
        """
        <a href="/main/simple/bar/">bar</a>
        <a href="/main/simple/baz/">baz</a>
        <a href="/main/simple/foo/">foo</a>
        """,
        "",
        "",
        "",
    ]

    def download(url, output, **kwargs):
        _ = kwargs  # buildifier: disable=unused-variable
        downloads[url[0]] = output
        return struct(success = True)

    simpleapi_download(
        ctx = struct(
            getenv = {}.get,
            download = download,
            report_progress = lambda _: None,
            # We will first add a download to the list, so this is a poor man's `next(foo)`
            # implementation
            read = lambda i: reads[len(downloads) - 1],
            path = lambda i: "path/for/" + i,
        ),
        attr = struct(
            index_url_overrides = {},
            index_url = "https://example.com/main/simple/",
            extra_index_urls = [],
            sources = {"bar": ["1.0"], "baz": ["1.0"], "foo": ["1.0"]},
            envsubst = [],
        ),
        cache = pypi_cache(),
        parallel_download = False,
        get_auth = lambda ctx, urls, ctx_attr: struct(),
    )

    env.expect.that_dict(downloads).contains_exactly({
        "https://example.com/main/simple/": "path/for/https___example_com_main_simple.html",
        "https://example.com/main/simple/bar/": "path/for/https___example_com_main_simple_bar.html",
        "https://example.com/main/simple/baz/": "path/for/https___example_com_main_simple_baz.html",
        "https://example.com/main/simple/foo/": "path/for/https___example_com_main_simple_foo.html",
    })

_tests.append(_test_download_url)

def _test_download_url_parallel(env):
    downloads = {}
    reads = [
        # The first read is the index which seeds the downloads later
        """
        <a href="/main/simple/bar/">bar</a>
        <a href="/main/simple/baz/">baz</a>
        <a href="/main/simple/foo/">foo</a>
        """,
        "",
        "",
        "",
        "",
    ]

    def download(url, output, **kwargs):
        _ = kwargs  # buildifier: disable=unused-variable
        downloads[url[0]] = output
        return struct(wait = lambda: struct(success = True))

    simpleapi_download(
        ctx = struct(
            getenv = {}.get,
            download = download,
            report_progress = lambda _: None,
            # We will first add a download to the list, so this is a poor man's `next(foo)`
            # implementation. We use 2 because we will enqueue 2 downloads in parallel.
            read = lambda i: reads[len(downloads) - 2],
            path = lambda i: "path/for/" + i,
        ),
        attr = struct(
            index_url_overrides = {},
            index_url = "https://example.com/default/simple/",
            extra_index_urls = ["https://example.com/extra/simple/"],
            sources = {"bar": None, "baz": None, "foo": None},
            envsubst = [],
        ),
        cache = pypi_cache(),
        parallel_download = True,
        get_auth = lambda ctx, urls, ctx_attr: struct(),
    )

    env.expect.that_dict(downloads).contains_exactly({
        "https://example.com/default/simple/": "path/for/https___example_com_default_simple.html",
        "https://example.com/extra/simple/": "path/for/https___example_com_extra_simple.html",
        "https://example.com/extra/simple/bar/": "path/for/https___example_com_extra_simple_bar.html",
        "https://example.com/extra/simple/baz/": "path/for/https___example_com_extra_simple_baz.html",
        "https://example.com/extra/simple/foo/": "path/for/https___example_com_extra_simple_foo.html",
    })

_tests.append(_test_download_url_parallel)

def _test_download_envsubst_url(env):
    downloads = {}
    reads = [
        # The first read is the index which seeds the downloads later
        """
        <a href="/main/simple/bar/">bar</a>
        <a href="/main/simple/baz/">baz</a>
        <a href="/main/simple/foo/">foo</a>
        """,
        "",
        "",
        "",
    ]

    def download(url, output, **kwargs):
        _ = kwargs  # buildifier: disable=unused-variable
        downloads[url[0]] = output
        return struct(success = True)

    simpleapi_download(
        ctx = struct(
            getenv = {"INDEX_URL": "https://example.com/main/simple/"}.get,
            download = download,
            report_progress = lambda _: None,
            # We will first add a download to the list, so this is a poor man's `next(foo)`
            # implementation
            read = lambda i: reads[len(downloads) - 1],
            path = lambda i: "path/for/" + i,
        ),
        attr = struct(
            index_url_overrides = {},
            index_url = "$INDEX_URL",
            extra_index_urls = [],
            sources = {"bar": None, "baz": None, "foo": None},
            envsubst = ["INDEX_URL"],
        ),
        cache = pypi_cache(),
        parallel_download = False,
        get_auth = lambda ctx, urls, ctx_attr: struct(),
    )

    env.expect.that_dict(downloads).contains_exactly({
        "https://example.com/main/simple/": "path/for/~index_url~.html",
        "https://example.com/main/simple/bar/": "path/for/~index_url~_bar.html",
        "https://example.com/main/simple/baz/": "path/for/~index_url~_baz.html",
        "https://example.com/main/simple/foo/": "path/for/~index_url~_foo.html",
    })

_tests.append(_test_download_envsubst_url)

def simpleapi_download_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)

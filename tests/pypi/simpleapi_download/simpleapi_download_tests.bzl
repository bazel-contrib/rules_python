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

_tests = []

def _test_simple(env):
    calls = []

    def read_simpleapi(ctx, url, versions, attr, cache, get_auth, block):
        _ = ctx  # buildifier: disable=unused-variable
        _ = attr
        _ = cache
        _ = get_auth
        _ = versions
        env.expect.that_bool(block).equals(False)
        calls.append(url)
        if "foo" in url and "main" in url:
            return struct(
                output = "",
                success = False,
            )
        else:
            return struct(
                output = struct(
                    sdists = {"deadbeef": url.strip("/").split("/")[-1]},
                    whls = {"deadb33f": url.strip("/").split("/")[-1]},
                    sha256s_by_version = {"fizz": url.strip("/").split("/")[-1]},
                ),
                success = True,
            )

    contents = simpleapi_download(
        ctx = struct(
            getenv = {}.get,
            report_progress = lambda _: None,
        ),
        attr = struct(
            index_url_overrides = {},
            index_url = "main",
            extra_index_urls = ["extra"],
            sources = {"bar": None, "baz": None, "foo": None},
            envsubst = [],
        ),
        cache = pypi_cache(),
        parallel_download = True,
        read_simpleapi = read_simpleapi,
    )

    env.expect.that_collection(calls).contains_exactly([
        "extra/foo/",
        "main/bar/",
        "main/baz/",
        "main/foo/",
    ])
    env.expect.that_dict(contents).contains_exactly({
        "bar": struct(
            index_url = "main/bar/",
            sdists = {"deadbeef": "bar"},
            sha256s_by_version = {"fizz": "bar"},
            whls = {"deadb33f": "bar"},
        ),
        "baz": struct(
            index_url = "main/baz/",
            sdists = {"deadbeef": "baz"},
            sha256s_by_version = {"fizz": "baz"},
            whls = {"deadb33f": "baz"},
        ),
        "foo": struct(
            index_url = "extra/foo/",
            sdists = {"deadbeef": "foo"},
            sha256s_by_version = {"fizz": "foo"},
            whls = {"deadb33f": "foo"},
        ),
    })

_tests.append(_test_simple)

def _test_fail(env):
    calls = []
    fails = []

    def read_simpleapi(ctx, url, versions, attr, cache, get_auth, block):
        _ = ctx  # buildifier: disable=unused-variable
        _ = attr
        _ = cache
        _ = get_auth
        _ = versions
        env.expect.that_bool(block).equals(False)
        calls.append(url)
        if "foo" in url:
            return struct(
                output = "",
                success = False,
            )
        if "bar" in url:
            return struct(
                output = "",
                success = False,
            )
        else:
            return struct(
                output = struct(
                    sdists = {},
                    whls = {},
                    sha256s_by_version = {},
                ),
                success = True,
            )

    simpleapi_download(
        ctx = struct(
            getenv = {}.get,
            report_progress = lambda _: None,
        ),
        attr = struct(
            index_url_overrides = {
                "foo": "invalid",
            },
            index_url = "main",
            extra_index_urls = ["extra"],
            sources = {"bar": None, "baz": None, "foo": None},
            envsubst = [],
        ),
        cache = pypi_cache(),
        parallel_download = True,
        read_simpleapi = read_simpleapi,
        _fail = fails.append,
    )

    env.expect.that_collection(fails).contains_exactly([
        """
Failed to download metadata of the following packages from urls:
{
    "bar": ["main", "extra"],
    "foo": "invalid",
}

If you would like to skip downloading metadata for these packages please add 'simpleapi_skip=[
    "bar",
    "foo",
]' to your 'pip.parse' call.
""",
    ])
    env.expect.that_collection(calls).contains_exactly([
        "invalid/foo/",
        "main/bar/",
        "main/baz/",
        "invalid/foo/",
        "extra/bar/",
    ])

_tests.append(_test_fail)

def _test_download_url(env):
    downloads = {}

    def download(url, output, **kwargs):
        _ = kwargs  # buildifier: disable=unused-variable
        downloads[url[0]] = output
        return struct(success = True)

    simpleapi_download(
        ctx = struct(
            getenv = {}.get,
            download = download,
            report_progress = lambda _: None,
            read = lambda i: "contents of " + i,
            path = lambda i: "path/for/" + i,
        ),
        attr = struct(
            index_url_overrides = {},
            index_url = "https://example.com/main/simple/",
            extra_index_urls = [],
            sources = {"bar": None, "baz": None, "foo": None},
            envsubst = [],
        ),
        cache = pypi_cache(),
        parallel_download = False,
        get_auth = lambda ctx, urls, ctx_attr: struct(),
    )

    env.expect.that_dict(downloads).contains_exactly({
        "https://example.com/main/simple/bar/": "path/for/https___example_com_main_simple_bar.html",
        "https://example.com/main/simple/baz/": "path/for/https___example_com_main_simple_baz.html",
        "https://example.com/main/simple/foo/": "path/for/https___example_com_main_simple_foo.html",
    })

_tests.append(_test_download_url)

def _test_download_url_parallel(env):
    downloads = {}

    def download(url, output, **kwargs):
        _ = kwargs  # buildifier: disable=unused-variable
        downloads[url[0]] = output
        return struct(wait = lambda: struct(success = True))

    simpleapi_download(
        ctx = struct(
            getenv = {}.get,
            download = download,
            report_progress = lambda _: None,
            read = lambda i: "contents of " + i,
            path = lambda i: "path/for/" + i,
        ),
        attr = struct(
            index_url_overrides = {},
            index_url = "https://example.com/main/simple/",
            extra_index_urls = [],
            sources = {"bar": None, "baz": None, "foo": None},
            envsubst = [],
        ),
        cache = pypi_cache(),
        parallel_download = True,
        get_auth = lambda ctx, urls, ctx_attr: struct(),
    )

    env.expect.that_dict(downloads).contains_exactly({
        "https://example.com/main/simple/bar/": "path/for/https___example_com_main_simple_bar.html",
        "https://example.com/main/simple/baz/": "path/for/https___example_com_main_simple_baz.html",
        "https://example.com/main/simple/foo/": "path/for/https___example_com_main_simple_foo.html",
    })

_tests.append(_test_download_url_parallel)

def _test_download_envsubst_url(env):
    downloads = {}

    def download(url, output, **kwargs):
        _ = kwargs  # buildifier: disable=unused-variable
        downloads[url[0]] = output
        return struct(success = True)

    simpleapi_download(
        ctx = struct(
            getenv = {"INDEX_URL": "https://example.com/main/simple/"}.get,
            download = download,
            report_progress = lambda _: None,
            read = lambda i: "contents of " + i,
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

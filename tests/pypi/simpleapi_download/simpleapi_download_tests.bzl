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
load("//python/private/pypi:simpleapi_download.bzl", "simpleapi_download")  # buildifier: disable=bzl-visibility

_tests = []

def _test_simple(env):
    calls = []

    def read_simpleapi(ctx, url, attr, cache, block):
        _ = ctx  # buildifier: disable=unused-variable
        _ = attr
        _ = cache
        env.expect.that_bool(block).equals(False)
        calls.append(url)
        if "foo" in url and "main" in url:
            return struct(
                output = "",
                success = False,
            )
        else:
            return struct(
                output = "data from {}".format(url),
                success = True,
            )

    contents = simpleapi_download(
        ctx = struct(
            os = struct(environ = {}),
        ),
        attr = struct(
            index_url_overrides = {},
            index_url = "main",
            extra_index_urls = ["extra"],
            sources = ["foo", "bar", "baz"],
            envsubst = [],
        ),
        cache = {},
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
        "bar": "data from main/bar/",
        "baz": "data from main/baz/",
        "foo": "data from extra/foo/",
    })

_tests.append(_test_simple)

def _test_fail(env):
    calls = []
    fails = []

    def read_simpleapi(ctx, url, attr, cache, block):
        _ = ctx  # buildifier: disable=unused-variable
        _ = attr
        _ = cache
        env.expect.that_bool(block).equals(False)
        calls.append(url)
        if "foo" in url:
            return struct(
                output = "",
                success = False,
            )
        else:
            return struct(
                output = "data from {}".format(url),
                success = True,
            )

    simpleapi_download(
        ctx = struct(
            os = struct(environ = {}),
        ),
        attr = struct(
            index_url_overrides = {},
            index_url = "main",
            extra_index_urls = ["extra"],
            sources = ["foo", "bar", "baz"],
            envsubst = [],
        ),
        cache = {},
        parallel_download = True,
        read_simpleapi = read_simpleapi,
        _fail = fails.append,
    )

    env.expect.that_collection(fails).contains_exactly([
        """Failed to download metadata for ["foo"] for from urls: ["main", "extra"]""",
    ])
    env.expect.that_collection(calls).contains_exactly([
        "extra/foo/",
        "main/bar/",
        "main/baz/",
        "main/foo/",
    ])

_tests.append(_test_fail)

def simpleapi_download_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)

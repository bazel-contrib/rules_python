# Copyright 2023 The Bazel Authors. All rights reserved.
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
load("@rules_testing//lib:truth.bzl", "subjects")
load("//python/private/pypi:parse_simpleapi_html.bzl", "parse_simpleapi_html")  # buildifier: disable=bzl-visibility

_tests = []

def _generate_html(*items):
    return """\
<html>
  <head>
    <meta name="pypi:repository-version" content="1.1">
    <title>Links for foo</title>
  </head>
  <body>
    <h1>Links for cengal</h1>
{}
</body>
</html>
""".format(
        "\n".join([
            "<a {}>{}</a><br />".format(
                " ".join(item.attrs),
                item.filename,
            )
            for item in items
        ]),
    )

def _test_index(env):
    # buildifier: disable=unsorted-dict-items
    tests = [
        (
            [
                struct(attrs = ['href="/simple/foo/"'], filename = "foo"),
                struct(attrs = ['href="./b-ar/"'], filename = "b-._.-aR"),
            ],
            {
                "b_ar": "./b-ar/",
                "foo": "/simple/foo/",
            },
        ),
    ]

    for (input, want) in tests:
        html = _generate_html(*input)
        got = parse_simpleapi_html(content = html, parse_index = True)

        env.expect.that_dict(got).contains_exactly(want)

_tests.append(_test_index)

def _test_sdist(env):
    # buildifier: disable=unsorted-dict-items
    tests = [
        (
            struct(
                attrs = [
                    'href="https://example.org/full-url/foo-0.0.1.tar.gz#sha256=deadbeefasource"',
                    'data-requires-python="&gt;=3.7"',
                ],
                filename = "foo-0.0.1.tar.gz",
            ),
            struct(
                filename = "foo-0.0.1.tar.gz",
                sha256 = "deadbeefasource",
                url = "https://example.org/full-url/foo-0.0.1.tar.gz",
                yanked = None,
                version = "0.0.1",
            ),
        ),
        (
            struct(
                attrs = [
                    'href="https://example.org/full-url/foo-0.0.1.tar.gz#sha256=deadbeefasource"',
                    'data-requires-python=">=3.7"',
                    "data-yanked",
                ],
                filename = "foo-0.0.1.tar.gz",
            ),
            struct(
                filename = "foo-0.0.1.tar.gz",
                sha256 = "deadbeefasource",
                url = "https://example.org/full-url/foo-0.0.1.tar.gz",
                version = "0.0.1",
                yanked = "",
            ),
        ),
        (
            struct(
                attrs = [
                    'href="https://example.org/full-url/foo-0.0.1.tar.gz#sha256=deadbeefasource"',
                    'data-requires-python="<=3.7"',
                    "data-yanked=\"Something &#10;with &quot;quotes&quot;&#10;over two lines\"",
                ],
                filename = "foo-0.0.1.tar.gz",
            ),
            struct(
                filename = "foo-0.0.1.tar.gz",
                sha256 = "deadbeefasource",
                url = "https://example.org/full-url/foo-0.0.1.tar.gz",
                version = "0.0.1",
                # NOTE @aignas 2026-03-09: we preserve the white space
                yanked = "Something \nwith \"quotes\"\nover two lines",
            ),
        ),
        (
            struct(
                attrs = [
                    'href="https://example.org/full-url/foo-0.0.1.tar.gz#sha256=deadbeefasource"',
                    'data-requires-python="&gt;=3.7"',
                    'data-yanked=""',
                ],
                filename = "foo-0.0.1.tar.gz",
            ),
            struct(
                filename = "foo-0.0.1.tar.gz",
                sha256 = "deadbeefasource",
                url = "https://example.org/full-url/foo-0.0.1.tar.gz",
                version = "0.0.1",
                yanked = "",
            ),
        ),
    ]

    for (input, want) in tests:
        html = _generate_html(input)
        got = parse_simpleapi_html(content = html)
        env.expect.that_collection(got.sdists).has_size(1)
        env.expect.that_collection(got.whls).has_size(0)
        env.expect.that_collection(got.sha256s_by_version).has_size(1)
        if not got:
            fail("expected at least one element, but did not get anything from:\n{}".format(html))

        actual = env.expect.that_struct(
            got.sdists[want.sha256],
            attrs = dict(
                filename = subjects.str,
                sha256 = subjects.str,
                url = subjects.str,
                yanked = subjects.str,
                version = subjects.str,
            ),
        )
        actual.filename().equals(want.filename)
        actual.sha256().equals(want.sha256)
        actual.url().equals(want.url)
        actual.yanked().equals(want.yanked)
        actual.version().equals(want.version)

_tests.append(_test_sdist)

def _test_whls(env):
    # buildifier: disable=unsorted-dict-items
    tests = [
        (
            struct(
                attrs = [
                    'href="https://example.org/full-url/foo-0.0.2-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl#sha256=deadbeef"',
                    'data-requires-python="&gt;=3.7"',
                    'data-dist-info-metadata="sha256=deadb00f"',
                    'data-core-metadata="sha256=deadb00f"',
                ],
                filename = "foo-0.0.2-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
            ),
            struct(
                filename = "foo-0.0.2-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
                metadata_sha256 = "deadb00f",
                metadata_url = "https://example.org/full-url/foo-0.0.2-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl.metadata",
                sha256 = "deadbeef",
                url = "https://example.org/full-url/foo-0.0.2-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
                version = "0.0.2",
                yanked = None,
            ),
        ),
        (
            struct(
                attrs = [
                    'href="https://example.org/full-url/foo-0.0.2-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl#sha256=deadbeef"',
                    'data-requires-python="&gt;=3.7"',
                    'data-dist-info-metadata="sha256=deadb00f"',
                    'data-core-metadata="sha256=deadb00f"',
                ],
                filename = "foo-0.0.2-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
            ),
            struct(
                filename = "foo-0.0.2-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
                metadata_sha256 = "deadb00f",
                metadata_url = "https://example.org/full-url/foo-0.0.2-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl.metadata",
                sha256 = "deadbeef",
                url = "https://example.org/full-url/foo-0.0.2-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
                version = "0.0.2",
                yanked = None,
            ),
        ),
        (
            struct(
                attrs = [
                    'href="https://example.org/full-url/foo-0.0.2-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl#sha256=deadbeef"',
                    'data-requires-python="&gt;=3.7"',
                    'data-core-metadata="sha256=deadb00f"',
                ],
                filename = "foo-0.0.2-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
            ),
            struct(
                filename = "foo-0.0.2-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
                metadata_sha256 = "deadb00f",
                metadata_url = "https://example.org/full-url/foo-0.0.2-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl.metadata",
                sha256 = "deadbeef",
                version = "0.0.2",
                url = "https://example.org/full-url/foo-0.0.2-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
                yanked = None,
            ),
        ),
        (
            struct(
                attrs = [
                    'href="https://example.org/full-url/foo-0.0.2-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl#sha256=deadbeef"',
                    'data-requires-python="&gt;=3.7"',
                    'data-dist-info-metadata="sha256=deadb00f"',
                ],
                filename = "foo-0.0.2-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
            ),
            struct(
                filename = "foo-0.0.2-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
                metadata_sha256 = "deadb00f",
                metadata_url = "https://example.org/full-url/foo-0.0.2-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl.metadata",
                sha256 = "deadbeef",
                version = "0.0.2",
                url = "https://example.org/full-url/foo-0.0.2-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
                yanked = None,
            ),
        ),
        (
            struct(
                attrs = [
                    'href="https://example.org/full-url/foo-0.0.2-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl#sha256=deadbeef"',
                    'data-requires-python="&gt;=3.7"',
                ],
                filename = "foo-0.0.2-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
            ),
            struct(
                filename = "foo-0.0.2-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
                metadata_sha256 = "",
                metadata_url = "",
                sha256 = "deadbeef",
                url = "https://example.org/full-url/foo-0.0.2-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
                version = "0.0.2",
                yanked = None,
            ),
        ),
    ]

    for (input, want) in tests:
        html = _generate_html(input)
        got = parse_simpleapi_html(content = html)
        env.expect.that_collection(got.sdists).has_size(0)
        env.expect.that_collection(got.whls).has_size(1)
        if not got:
            fail("expected at least one element, but did not get anything from:\n{}".format(html))

        actual = env.expect.that_struct(
            got.whls[want.sha256],
            attrs = dict(
                filename = subjects.str,
                metadata_sha256 = subjects.str,
                metadata_url = subjects.str,
                sha256 = subjects.str,
                url = subjects.str,
                yanked = subjects.str,
                version = subjects.str,
            ),
        )
        actual.filename().equals(want.filename)
        actual.metadata_sha256().equals(want.metadata_sha256)
        actual.metadata_url().equals(want.metadata_url)
        actual.sha256().equals(want.sha256)
        actual.url().equals(want.url)
        actual.yanked().equals(want.yanked)
        actual.version().equals(want.version)

_tests.append(_test_whls)

def parse_simpleapi_html_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)

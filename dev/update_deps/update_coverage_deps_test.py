"""Tests for parsing the coverage wheels from a uv.lock file."""

import tomllib

from dev.update_deps.update_coverage_deps import Whl, Whls, get_whls

_UV_LOCK = """
version = 1
requires-python = ">=3.9"

[[package]]
name = "coverage"
version = "1.0.0"
resolution-markers = [
    "python_full_version < '3.15'",
]
wheels = [
    { url = "https://example.org/coverage-1.0.0-py3-none-any.whl", hash = "sha256:aa" },
    { url = "https://example.org/coverage-1.0.0-cp39-cp39-win_amd64.whl", hash = "sha256:bb" },
]

[[package]]
name = "coverage"
version = "2.0.0"
resolution-markers = [
    "python_full_version >= '3.15' and sys_platform == 'linux'",
    "python_full_version >= '3.15' and sys_platform != 'linux'",
]
wheels = [
    { url = "https://example.org/coverage-2.0.0-py3-none-any.whl", hash = "sha256:cc" },
]

[[package]]
name = "other"
version = "0.0.0"
source = { virtual = "." }
"""


def test_get_whls():
    got = get_whls(tomllib.loads(_UV_LOCK), "coverage")

    assert got == [
        Whl(
            url="https://example.org/coverage-1.0.0-cp39-cp39-win_amd64.whl",
            hash="sha256:bb",
            marker="python_full_version < '3.15'",
        ),
        Whl(
            url="https://example.org/coverage-1.0.0-py3-none-any.whl",
            hash="sha256:aa",
            marker="python_full_version < '3.15'",
        ),
        Whl(
            url="https://example.org/coverage-2.0.0-py3-none-any.whl",
            hash="sha256:cc",
            marker="(python_full_version >= '3.15' and sys_platform == 'linux') or (python_full_version >= '3.15' and sys_platform != 'linux')",
        ),
    ]


def test_get_whls_unknown_package():
    assert get_whls(tomllib.loads(_UV_LOCK), "unknown") == []


def test_render():
    got = repr(
        Whls(
            [
                Whl(
                    url="https://example.org/foo.whl",
                    hash="sha256:aa",
                    marker="python_version < '3.15'",
                ),
                Whl(
                    url="https://example.org/bar.whl",
                    hash="sha256:bb",
                    marker="",
                ),
            ]
        )
    )

    assert (
        got
        == """\
[
    struct(
        url = "https://example.org/foo.whl",
        hash = "sha256:aa",
        marker = "python_version < '3.15'",
    ),
    struct(
        url = "https://example.org/bar.whl",
        hash = "sha256:bb",
        marker = "",
    ),
]"""
    )

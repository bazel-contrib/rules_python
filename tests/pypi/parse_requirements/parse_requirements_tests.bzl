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
load("//python/private:repo_utils.bzl", "REPO_DEBUG_ENV_VAR", "REPO_VERBOSITY_ENV_VAR", "repo_utils")  # buildifier: disable=bzl-visibility
load("//python/private/pypi:parse_requirements.bzl", "select_requirement", _parse_requirements = "parse_requirements")  # buildifier: disable=bzl-visibility
load("//python/private/pypi:pep508_env.bzl", pep508_env = "env")  # buildifier: disable=bzl-visibility
load("//tests/support/mocks:mocks.bzl", "mocks")

def _mock_ctx():
    testdata = {
        "requirements_direct": """\
foo[extra] @ https://some-url/package.whl
""",
        "requirements_direct_sdist": """
foo @ https://github.com/org/foo/downloads/foo-1.1.tar.gz
""",
        "requirements_extra_args": """\
--index-url=example.org

foo[extra]==0.0.1 \
    --hash=sha256:deadbeef
""",
        "requirements_foo": """\
foo==0.0.1 \
    --hash=sha256:deadb00f
""",
        "requirements_foo_local": """\
foo==0.0.1+local \
    --hash=sha256:deadbeef
""",
        "requirements_git": """
foo @ git+https://github.com/org/foo.git@deadbeef
""",
        "requirements_linux": """\
foo==0.0.3 --hash=sha256:deadbaaf --hash=sha256:5d15t
""",
        # download_only = True
        "requirements_linux_download_only": """\
--platform=manylinux_2_17_x86_64
--python-version=39
--implementation=cp
--abi=cp39

foo==0.0.1 --hash=sha256:deadbeef
bar==0.0.1 --hash=sha256:deadb00f
""",
        "requirements_lock": """\
foo[extra]==0.0.1 --hash=sha256:deadbeef
""",
        "requirements_lock_dupe": """\
foo[extra,extra_2]==0.0.1 --hash=sha256:deadbeef
foo==0.0.1 --hash=sha256:deadbeef
foo[extra]==0.0.1 --hash=sha256:deadbeef
""",
        "requirements_marker": """\
foo[extra]==0.0.1 ; os_name == 'nt' --hash=sha256:deadbeef
bar==0.0.1 --hash=sha256:deadbeef
""",
        "requirements_multi_version": """\
foo==0.0.1; python_full_version < '3.10.0' \
    --hash=sha256:deadbeef
foo==0.0.2; python_full_version >= '3.10.0' \
    --hash=sha256:deadb11f
boo==0.0.4; python_full_version < '3.10.0' \
    --hash=sha256:deadbaaf
""",
        "requirements_optional_hash": """
bar==0.0.4 @ https://example.org/bar-0.0.4.whl
foo==0.0.5 @ https://example.org/foo-0.0.5.whl --hash=sha256:deadbeef
""",
        "requirements_osx": """\
foo==0.0.3 --hash=sha256:deadbaaf --hash=sha256:deadb11f --hash=sha256:5d15t
""",
        "requirements_osx_download_only": """\
--platform=macosx_10_9_arm64
--python-version=39
--implementation=cp
--abi=cp39

foo==0.0.3 --hash=sha256:deadbaaf
""",
        "requirements_windows": """\
foo[extra]==0.0.2 --hash=sha256:deadbeef
bar==0.0.1 --hash=sha256:deadb00f
""",
        "uv_lock_empty": """{"package":[]}""",
        "uv_lock_foo": """{"package":[{"dependencies":[{"extra":"extra","name":"bar"}],"name":"foo","source":{"registry":"https://pypi.org/simple"},"version":"0.0.1","wheels":[{"hash":"sha256:deadbeef","url":"https://files.pythonhosted.org/packages/foo-0.0.1-py3-none-any.whl"}]}]}""",
        "uv_lock_foo_bar": """{"package":[{"name":"bar","version":"0.0.1","source":{"registry":"https://pypi.org/simple"},"sdist":{"hash":"sha256:deadb00f","url":"https://files.pythonhosted.org/packages/bar-0.0.1.tar.gz"}},{"name":"foo","version":"0.0.1","source":{"registry":"https://pypi.org/simple"},"wheels":[{"hash":"sha256:deadbeef","url":"https://files.pythonhosted.org/packages/foo-0.0.1-py3-none-any.whl"}]}]}""",
        "uv_lock_foo_dep_extra": """{"package":[{"name":"bar","version":"0.0.2","source":{"registry":"https://pypi.org/simple"},"wheels":[{"hash":"sha256:deadbeef","url":"https://files.pythonhosted.org/packages/bar-0.0.2-py3-none-any.whl"}]},{"name":"foo","version":"0.0.1","source":{"registry":"https://pypi.org/simple"},"dependencies":[{"name":"bar","extra":["extra1"]}],"wheels":[{"hash":"sha256:baadbeef","url":"https://files.pythonhosted.org/packages/foo-0.0.1-py3-none-any.whl"}]}]}""",
        "uv_lock_foo_multi_versions": """{"package":[{"name":"foo","source":{"registry":"https://pypi.org/simple"},"version":"0.0.1","wheels":[{"hash":"sha256:deadbeef","url":"https://files.pythonhosted.org/packages/foo-0.0.1-py3-none-any.whl"}]},{"name":"foo","source":{"registry":"https://pypi.org/simple"},"version":"0.0.2","wheels":[{"hash":"sha256:deadb11f","url":"https://files.pythonhosted.org/packages/foo-0.0.2-py3-none-any.whl"}]}]}""",
        "uv_lock_foo_multi_wheel_dedup": """{"package":[{"name":"foo","version":"0.0.1","source":{"registry":"https://pypi.org/simple"},"wheels":[{"hash":"sha256:aaa","url":"https://files.pythonhosted.org/packages/foo-0.0.1-cp39-cp39-manylinux_2_17_x86_64.whl"},{"hash":"sha256:bbb","url":"https://files.pythonhosted.org/packages/foo-0.0.1-py3-none-any.whl"}]}]}""",
        "uv_lock_foo_only": """{"package":[{"name":"foo","source":{"registry":"https://pypi.org/simple"},"version":"0.0.2"}]}""",
        "uv_lock_foo_optional_deps": """{"package":[{"name":"foo","version":"0.0.1","source":{"registry":"https://pypi.org/simple"},"optional-dependencies":{"extra1":[],"extra2":[]},"wheels":[{"hash":"sha256:deadbeef","url":"https://files.pythonhosted.org/packages/foo-0.0.1-py3-none-any.whl"}]}]}""",
        "uv_lock_foo_requires_dist_extras": """{"package":[{"name":"foo","version":"0.0.1","source":{"registry":"https://pypi.org/simple"},"wheels":[{"hash":"sha256:deadbeef","url":"https://files.pythonhosted.org/packages/foo-0.0.1-py3-none-any.whl"}]},{"name":"root-pkg","source":{"virtual":"."},"version":"0.0.0","dependencies":[{"name":"foo"}],"metadata":{"requires-dist":[{"name":"foo","extras":["all"]}]}}]}""",
        "uv_lock_foo_resolution_markers_dedup": """{"package":[{"name":"foo","source":{"registry":"https://pypi.org/simple"},"version":"0.0.1","resolution-markers":["sys_platform == 'linux'"],"wheels":[{"hash":"sha256:aaa","url":"https://files.pythonhosted.org/packages/foo-0.0.1-cp39-cp39-manylinux_2_17_x86_64.whl"},{"hash":"sha256:bbb","url":"https://files.pythonhosted.org/packages/foo-0.0.1-py3-none-any.whl"}]},{"name":"foo","source":{"registry":"https://pypi.org/simple"},"version":"0.0.2","resolution-markers":["sys_platform == 'darwin'"],"wheels":[{"hash":"sha256:ccc","url":"https://files.pythonhosted.org/packages/foo-0.0.2-cp39-cp39-macosx_11_0_arm64.whl"},{"hash":"sha256:ddd","url":"https://files.pythonhosted.org/packages/foo-0.0.2-py3-none-any.whl"}]}]}""",
        "uv_lock_foo_sdist": """{"package":[{"name":"foo","sdist":{"hash":"sha256:feedcafe","url":"https://files.pythonhosted.org/packages/foo-0.0.1.tar.gz"},"source":{"registry":"https://pypi.org/simple"},"version":"0.0.1","wheels":[{"hash":"sha256:deadbeef","url":"https://files.pythonhosted.org/packages/foo-0.0.1-py3-none-any.whl"}]}]}""",
        "uv_lock_foo_virtual": """{"package":[{"name":"foo","source":{"registry":"https://pypi.org/simple"},"version":"0.0.1","wheels":[{"hash":"sha256:deadbeef","url":"https://files.pythonhosted.org/packages/foo-0.0.1-py3-none-any.whl"}]},{"name":"virtual-pkg","source":{"virtual":true},"version":"0.0.0"}]}""",
        "uv_lock_foo_with_extras": """{"package":[{"name":"foo","provides-extras":["extra"],"source":{"registry":"https://pypi.org/simple"},"version":"0.0.1","wheels":[{"hash":"sha256:deadbeef","url":"https://files.pythonhosted.org/packages/foo-0.0.1-py3-none-any.whl"}]}]}""",
        "uv_lock_git_vcs": """{"package":[{"name":"foo","source":{"git":"https://github.com/org/foo.git"},"version":"0.1.0"}]}""",
        "uv_lock_rules_python_pkg": """{"package":[{"name":"rules_python","source":{"registry":"https://pypi.org/simple"},"version":"0.0.1","wheels":[{"hash":"sha256:deadbeef","url":"https://files.pythonhosted.org/packages/rules_python-0.0.1-py3-none-any.whl"}]}]}""",
    }

    return mocks.mctx(
        os_name = "linux",
        arch_name = "x86_64",
        mock_files = testdata,
    )

_tests = []

def _make_platforms(platform_names):
    """Create minimal platform structs for testing, matching py3-none-any wheels."""
    platforms = {}
    for name in platform_names:
        platforms[name] = struct(
            env = pep508_env(python_version = "3.11.0", os = "linux", arch = "x86_64"),
            whl_abi_tags = ["none"],
            whl_platform_tags = ["any"],
        )
    return platforms

def parse_requirements(debug = False, **kwargs):
    """Get requirements by calling the original parse_requirements.

    Args:
      debug: If True, set verbosity to TRACE.
      **kwargs: forwarded to the underlying function.

    Returns:
      The result of the underlying parse_requirements call.
    """
    kwargs.setdefault("toml_decode", json.decode)

    # Provide default platforms when not specified.
    if "platforms" not in kwargs:
        if "requirements_by_platform" in kwargs:
            platform_names = {}
            for _plats in kwargs["requirements_by_platform"].values():
                for _p in _plats:
                    platform_names[_p] = None
            platform_names = sorted(platform_names)
            kwargs["platforms"] = _make_platforms(platform_names)
        elif "uv_lock" in kwargs:
            kwargs["platforms"] = _make_platforms(["linux_x86_64"])

    return _parse_requirements(
        ctx = _mock_ctx(),
        logger = repo_utils.logger(struct(
            getenv = {
                REPO_DEBUG_ENV_VAR: "1",
                REPO_VERBOSITY_ENV_VAR: "TRACE" if debug else "INFO",
            }.get,
        ), "unit-test"),
        **kwargs
    )

def _test_simple(env):
    """Test basic parsing of a single ``requirements_lock`` file."""
    got = parse_requirements(
        requirements_by_platform = {
            "requirements_lock": ["linux_x86_64", "windows_x86_64"],
        },
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo[extra]==0.0.1 --hash=sha256:deadbeef",
                    target_platforms = [
                        "linux_x86_64",
                        "windows_x86_64",
                    ],
                    url = "",
                    filename = "",
                    sha256 = "",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_simple)

def _test_direct_urls_integration(env):
    """Check that we are using the filename from index_sources."""
    got = parse_requirements(
        requirements_by_platform = {
            "requirements_direct": ["linux_x86_64"],
            "requirements_direct_sdist": ["osx_x86_64"],
        },
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = True,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    filename = "foo-1.1.tar.gz",
                    requirement_line = "foo @ https://github.com/org/foo/downloads/foo-1.1.tar.gz",
                    sha256 = "",
                    target_platforms = ["osx_x86_64"],
                    url = "https://github.com/org/foo/downloads/foo-1.1.tar.gz",
                    yanked = None,
                ),
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    filename = "package.whl",
                    requirement_line = "foo[extra]",
                    sha256 = "",
                    target_platforms = ["linux_x86_64"],
                    url = "https://some-url/package.whl",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_direct_urls_integration)

def _test_direct_urls_no_extract(env):
    """Check that URL requirements are not dropped when extract_url_srcs=False."""
    got = parse_requirements(
        requirements_by_platform = {
            "requirements_direct": ["linux_x86_64"],
            "requirements_direct_sdist": ["osx_x86_64"],
        },
        extract_url_srcs = False,
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = True,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    filename = "",
                    requirement_line = "foo @ https://github.com/org/foo/downloads/foo-1.1.tar.gz",
                    sha256 = "",
                    target_platforms = ["osx_x86_64"],
                    url = "",
                    yanked = None,
                ),
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    filename = "",
                    requirement_line = "foo[extra] @ https://some-url/package.whl",
                    sha256 = "",
                    target_platforms = ["linux_x86_64"],
                    url = "",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_direct_urls_no_extract)

def _test_extra_pip_args(env):
    """Test that ``extra_pip_args`` are merged with per-requirement-file args."""
    got = parse_requirements(
        requirements_by_platform = {
            "requirements_extra_args": ["linux_x86_64"],
        },
        extra_pip_args = ["--trusted-host=example.org"],
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = ["--index-url=example.org", "--trusted-host=example.org"],
                    requirement_line = "foo[extra]==0.0.1 --hash=sha256:deadbeef",
                    target_platforms = [
                        "linux_x86_64",
                    ],
                    url = "",
                    filename = "",
                    sha256 = "",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_extra_pip_args)

def _test_dupe_requirements(env):
    """Test that duplicate requirement entries are deduplicated."""
    got = parse_requirements(
        requirements_by_platform = {
            "requirements_lock_dupe": ["linux_x86_64"],
        },
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo[extra,extra_2]==0.0.1 --hash=sha256:deadbeef",
                    target_platforms = ["linux_x86_64"],
                    url = "",
                    filename = "",
                    sha256 = "",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_dupe_requirements)

def _test_multi_os(env):
    """Test per-OS requirements parsing with ``select_requirement``."""
    got = parse_requirements(
        requirements_by_platform = {
            "requirements_linux": ["linux_x86_64"],
            "requirements_windows": ["windows_x86_64"],
        },
    )

    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "bar",
            index_url = "",
            is_exposed = False,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "bar",
                    extra_pip_args = [],
                    requirement_line = "bar==0.0.1 --hash=sha256:deadb00f",
                    target_platforms = ["windows_x86_64"],
                    url = "",
                    filename = "",
                    sha256 = "",
                    yanked = None,
                ),
            ],
        ),
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = True,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo==0.0.3 --hash=sha256:deadbaaf --hash=sha256:5d15t",
                    target_platforms = ["linux_x86_64"],
                    url = "",
                    filename = "",
                    sha256 = "",
                    yanked = None,
                ),
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo[extra]==0.0.2 --hash=sha256:deadbeef",
                    target_platforms = ["windows_x86_64"],
                    url = "",
                    filename = "",
                    sha256 = "",
                    yanked = None,
                ),
            ],
        ),
    ])
    env.expect.that_str(
        select_requirement(
            got[1].srcs,
            platform = "windows_x86_64",
        ).requirement_line,
    ).equals("foo[extra]==0.0.2 --hash=sha256:deadbeef")

_tests.append(_test_multi_os)

def _test_multi_os_legacy(env):
    """Test download-only per-OS requirements parsing."""
    got = parse_requirements(
        requirements_by_platform = {
            "requirements_linux_download_only": ["cp39_linux_x86_64"],
            "requirements_osx_download_only": ["cp39_osx_aarch64"],
        },
    )

    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "bar",
            index_url = "",
            is_exposed = False,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "bar",
                    extra_pip_args = ["--platform=manylinux_2_17_x86_64", "--python-version=39", "--implementation=cp", "--abi=cp39"],
                    requirement_line = "bar==0.0.1 --hash=sha256:deadb00f",
                    target_platforms = ["cp39_linux_x86_64"],
                    url = "",
                    filename = "",
                    sha256 = "",
                    yanked = None,
                ),
            ],
        ),
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = True,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = ["--platform=manylinux_2_17_x86_64", "--python-version=39", "--implementation=cp", "--abi=cp39"],
                    requirement_line = "foo==0.0.1 --hash=sha256:deadbeef",
                    target_platforms = ["cp39_linux_x86_64"],
                    url = "",
                    filename = "",
                    sha256 = "",
                    yanked = None,
                ),
                struct(
                    distribution = "foo",
                    extra_pip_args = ["--platform=macosx_10_9_arm64", "--python-version=39", "--implementation=cp", "--abi=cp39"],
                    requirement_line = "foo==0.0.3 --hash=sha256:deadbaaf",
                    target_platforms = ["cp39_osx_aarch64"],
                    url = "",
                    filename = "",
                    sha256 = "",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_multi_os_legacy)

def _test_select_requirement_none_platform(env):
    """Test that ``select_requirement`` returns the first src when platform is ``None``."""
    got = select_requirement(
        [
            struct(
                some_attr = "foo",
                target_platforms = ["linux_x86_64"],
            ),
        ],
        platform = None,
    )
    env.expect.that_str(got.some_attr).equals("foo")

_tests.append(_test_select_requirement_none_platform)

def _test_env_marker_resolution(env):
    """Test environment marker resolution with platform env information."""

    got = parse_requirements(
        requirements_by_platform = {
            "requirements_marker": ["cp311_linux_super_exotic", "cp311_windows_x86_64"],
        },
        platforms = {
            "cp311_linux_super_exotic": struct(
                env = pep508_env(os = "linux", arch = "x86_64", python_version = "3.11.0"),
                whl_abi_tags = [],
                whl_platform_tags = [],
            ),
            "cp311_windows_x86_64": struct(
                env = pep508_env(os = "windows", arch = "x86_64", python_version = "3.11.0"),
                whl_abi_tags = [],
                whl_platform_tags = [],
            ),
        },
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "bar",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "bar",
                    extra_pip_args = [],
                    requirement_line = "bar==0.0.1 --hash=sha256:deadbeef",
                    target_platforms = ["cp311_linux_super_exotic", "cp311_windows_x86_64"],
                    url = "",
                    filename = "",
                    sha256 = "",
                    yanked = None,
                ),
            ],
        ),
        struct(
            name = "foo",
            index_url = "",
            is_exposed = False,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo[extra]==0.0.1 --hash=sha256:deadbeef",
                    target_platforms = ["cp311_windows_x86_64"],
                    url = "",
                    filename = "",
                    sha256 = "",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_env_marker_resolution)

def _test_different_package_version(env):
    """Test that different package versions across platforms are handled."""
    got = parse_requirements(
        requirements_by_platform = {
            "requirements_foo": ["linux_aarch64"],
            "requirements_foo_local": ["linux_x86_64"],
        },
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = True,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo==0.0.1 --hash=sha256:deadb00f",
                    target_platforms = ["linux_aarch64"],
                    url = "",
                    filename = "",
                    sha256 = "",
                    yanked = None,
                ),
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo==0.0.1+local --hash=sha256:deadbeef",
                    target_platforms = ["linux_x86_64"],
                    url = "",
                    filename = "",
                    sha256 = "",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_different_package_version)

def _test_different_package_extras(env):
    """Test that different extras across platforms are handled."""
    got = parse_requirements(
        requirements_by_platform = {
            "requirements_foo": ["linux_aarch64"],
            "requirements_lock": ["linux_x86_64"],
        },
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = True,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo==0.0.1 --hash=sha256:deadb00f",
                    target_platforms = ["linux_aarch64"],
                    url = "",
                    filename = "",
                    sha256 = "",
                    yanked = None,
                ),
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo[extra]==0.0.1 --hash=sha256:deadbeef",
                    target_platforms = ["linux_x86_64"],
                    url = "",
                    filename = "",
                    sha256 = "",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_different_package_extras)

def _test_optional_hash(env):
    """Test parsing of requirements with optional hashes and URLs."""
    got = parse_requirements(
        requirements_by_platform = {
            "requirements_optional_hash": ["linux_x86_64"],
        },
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "bar",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "bar",
                    extra_pip_args = [],
                    requirement_line = "bar==0.0.4",
                    target_platforms = ["linux_x86_64"],
                    url = "https://example.org/bar-0.0.4.whl",
                    filename = "bar-0.0.4.whl",
                    sha256 = "",
                    yanked = None,
                ),
            ],
        ),
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo==0.0.5",
                    target_platforms = ["linux_x86_64"],
                    url = "https://example.org/foo-0.0.5.whl",
                    filename = "foo-0.0.5.whl",
                    sha256 = "deadbeef",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_optional_hash)

def _test_git_sources(env):
    """Test parsing of git-sourced requirements."""
    got = parse_requirements(
        requirements_by_platform = {
            "requirements_git": ["linux_x86_64"],
        },
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo @ git+https://github.com/org/foo.git@deadbeef",
                    target_platforms = ["linux_x86_64"],
                    url = "",
                    filename = "",
                    sha256 = "",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_git_sources)

def _test_overlapping_shas_with_index_results(env):
    """Test that index results with overlapping shas are matched to the correct platform."""
    got = parse_requirements(
        requirements_by_platform = {
            "requirements_linux": ["cp39_linux_x86_64"],
            "requirements_osx": ["cp39_osx_x86_64"],
        },
        platforms = {
            "cp39_linux_x86_64": struct(
                env = pep508_env(
                    python_version = "3.9.0",
                    os = "linux",
                    arch = "x86_64",
                ),
                whl_abi_tags = ["none"],
                whl_platform_tags = ["any"],
            ),
            "cp39_osx_x86_64": struct(
                env = pep508_env(
                    python_version = "3.9.0",
                    os = "osx",
                    arch = "x86_64",
                ),
                whl_abi_tags = ["none"],
                whl_platform_tags = ["macosx_*_x86_64"],
            ),
        },
        get_index_urls = lambda _, __, **kwargs: {
            "foo": struct(
                index_url = "https://example.com",
                sdists = {
                    "5d15t": struct(
                        url = "sdist",
                        sha256 = "5d15t",
                        filename = "foo-0.0.1.tar.gz",
                        yanked = None,
                    ),
                },
                whls = {
                    "deadb11f": struct(
                        url = "super2",
                        sha256 = "deadb11f",
                        filename = "foo-0.0.1-py3-none-macosx_14_0_x86_64.whl",
                        yanked = None,
                    ),
                    "deadbaaf": struct(
                        url = "super2",
                        sha256 = "deadbaaf",
                        filename = "foo-0.0.1-py3-none-any.whl",
                        yanked = None,
                    ),
                },
            ),
        },
    )

    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "foo",
            index_url = "https://example.com",
            is_exposed = True,
            is_multiple_versions = True,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    filename = "foo-0.0.1-py3-none-any.whl",
                    requirement_line = "foo==0.0.3",
                    sha256 = "deadbaaf",
                    target_platforms = ["cp39_linux_x86_64"],
                    url = "super2",
                    yanked = None,
                ),
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    filename = "foo-0.0.1-py3-none-macosx_14_0_x86_64.whl",
                    requirement_line = "foo==0.0.3",
                    sha256 = "deadb11f",
                    target_platforms = ["cp39_osx_x86_64"],
                    url = "super2",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_overlapping_shas_with_index_results)

def _test_get_index_urls_different_versions(env):
    """Test that different versions from index URLs are matched correctly per platform."""
    got = parse_requirements(
        requirements_by_platform = {
            "requirements_multi_version": [
                "cp39_linux_x86_64",
                "cp310_linux_x86_64",
            ],
        },
        platforms = {
            "cp310_linux_x86_64": struct(
                env = pep508_env(
                    python_version = "3.10.0",
                    os = "linux",
                    arch = "x86_64",
                ),
                whl_abi_tags = ["none"],
                whl_platform_tags = ["any"],
            ),
            "cp39_linux_x86_64": struct(
                env = pep508_env(
                    python_version = "3.9.0",
                    os = "linux",
                    arch = "x86_64",
                ),
                whl_abi_tags = ["none"],
                whl_platform_tags = ["any"],
            ),
        },
        get_index_urls = lambda _, __, **kwargs: {
            "foo": struct(
                index_url = "",
                sdists = {},
                whls = {
                    "deadb11f": struct(
                        url = "super2",
                        sha256 = "deadb11f",
                        filename = "foo-0.0.2-py3-none-any.whl",
                        yanked = None,
                    ),
                    "deadbaaf": struct(
                        url = "super2",
                        sha256 = "deadbaaf",
                        filename = "foo-0.0.1-py3-none-any.whl",
                        yanked = None,
                    ),
                },
            ),
        },
    )

    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "boo",
            index_url = "",
            is_exposed = False,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "boo",
                    extra_pip_args = [],
                    filename = "",
                    requirement_line = "boo==0.0.4 --hash=sha256:deadbaaf",
                    sha256 = "",
                    target_platforms = ["cp39_linux_x86_64"],
                    url = "",
                    yanked = None,
                ),
            ],
        ),
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = True,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    filename = "",
                    requirement_line = "foo==0.0.1 --hash=sha256:deadbeef",
                    sha256 = "",
                    target_platforms = ["cp39_linux_x86_64"],
                    url = "",
                    yanked = None,
                ),
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    filename = "foo-0.0.2-py3-none-any.whl",
                    requirement_line = "foo==0.0.2",
                    sha256 = "deadb11f",
                    target_platforms = ["cp310_linux_x86_64"],
                    url = "super2",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_get_index_urls_different_versions)

def _test_get_index_urls_cross_platform(env):
    """Verifies that distributions from all requirement files are passed to ``get_index_urls``.

    This ensures the lockfile facts are platform-independent.
    """
    calls = []

    def _get_index_urls(_, distributions, **__):
        calls.append({k: list(v) for k, v in distributions.items()})
        return {}

    parse_requirements(
        requirements_by_platform = {
            "requirements_osx": ["cp39_osx_x86_64"],
            # requirements_windows has no matching platforms (simulating
            # a macOS build where windows-specific files aren't used).
            "requirements_windows": [],
        },
        platforms = {
            "cp39_osx_x86_64": struct(
                env = pep508_env(
                    python_version = "3.9.0",
                    os = "osx",
                    arch = "x86_64",
                ),
                whl_abi_tags = ["none"],
                whl_platform_tags = ["macosx_*_x86_64"],
            ),
        },
        get_index_urls = _get_index_urls,
    )

    # distributions must include packages from ALL files, even those with
    # no matching platforms:
    #   - foo: 0.0.2 from requirements_windows, 0.0.3 from requirements_osx
    #   - bar: 0.0.1 from requirements_windows only
    env.expect.that_collection(calls).contains_exactly([
        {
            "bar": ["0.0.1"],
            "foo": ["0.0.2", "0.0.3"],
        },
    ])

_tests.append(_test_get_index_urls_cross_platform)

def _test_get_index_urls_single_py_version(env):
    """Test index URL matching when only a single Python version is used."""
    got = parse_requirements(
        requirements_by_platform = {
            "requirements_multi_version": [
                "cp310_linux_x86_64",
            ],
        },
        platforms = {
            "cp310_linux_x86_64": struct(
                env = pep508_env(
                    python_version = "3.10.0",
                    os = "linux",
                    arch = "x86_64",
                ),
                whl_abi_tags = ["none"],
                whl_platform_tags = ["any"],
            ),
        },
        get_index_urls = lambda _, __, **kwargs: {
            "foo": struct(
                index_url = "",
                sdists = {},
                whls = {
                    "deadb11f": struct(
                        url = "super2",
                        sha256 = "deadb11f",
                        filename = "foo-0.0.2-py3-none-any.whl",
                        yanked = None,
                    ),
                },
            ),
        },
    )

    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    filename = "foo-0.0.2-py3-none-any.whl",
                    requirement_line = "foo==0.0.2",
                    sha256 = "deadb11f",
                    target_platforms = ["cp310_linux_x86_64"],
                    url = "super2",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_get_index_urls_single_py_version)

def _test_get_index_urls_all_versions(env):
    """Test that all versions from all requirement files are passed to ``get_index_urls``."""
    calls = []

    def _get_index_urls(_, distributions, **__):
        calls.append({k: list(v) for k, v in distributions.items()})
        return {}

    parse_requirements(
        requirements_by_platform = {
            "requirements_multi_version": ["cp39_linux_x86_64"],
        },
        platforms = {
            "cp39_linux_x86_64": struct(
                env = pep508_env(
                    python_version = "3.9.0",
                    os = "linux",
                    arch = "x86_64",
                ),
                whl_abi_tags = ["none"],
                whl_platform_tags = ["any"],
            ),
        },
        get_index_urls = _get_index_urls,
    )

    env.expect.that_collection(calls).contains_exactly([
        {
            # boo should be also passed even though it is present on one platform.
            "boo": ["0.0.4"],
            # Both versions 0.0.1 and 0.0.2 should be passed to get_index_urls, even
            # though only 0.0.1 matches the cp39_linux_x86_64 platform markers.
            "foo": ["0.0.1", "0.0.2"],
        },
    ])

_tests.append(_test_get_index_urls_all_versions)

def _test_uv_lock_consistent(env):
    """Test that uv_lock with requirements_by_platform uses correct platforms."""
    got = parse_requirements(
        requirements_by_platform = {
            "requirements_lock": ["linux_x86_64", "windows_x86_64"],
        },
        uv_lock = "uv_lock_foo_with_extras",
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo[extra]==0.0.1",
                    target_platforms = ["linux_x86_64", "windows_x86_64"],
                    filename = "foo-0.0.1-py3-none-any.whl",
                    sha256 = "deadbeef",
                    url = "https://files.pythonhosted.org/packages/foo-0.0.1-py3-none-any.whl",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_uv_lock_consistent)

def _test_uv_lock_primary_source(env):
    """Test that uv.lock can be used as the sole source without requirements files."""
    got = parse_requirements(
        uv_lock = "uv_lock_foo_sdist",
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo==0.0.1",
                    target_platforms = ["linux_x86_64"],
                    filename = "foo-0.0.1-py3-none-any.whl",
                    sha256 = "deadbeef",
                    url = "https://files.pythonhosted.org/packages/foo-0.0.1-py3-none-any.whl",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_uv_lock_primary_source)

def _test_uv_lock_primary_source_multiple_versions(env):
    """Test that uv.lock with multiple versions of the same package works."""
    got = parse_requirements(
        uv_lock = "uv_lock_foo_multi_versions",
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = True,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo==0.0.1",
                    target_platforms = ["linux_x86_64"],
                    filename = "foo-0.0.1-py3-none-any.whl",
                    sha256 = "deadbeef",
                    url = "https://files.pythonhosted.org/packages/foo-0.0.1-py3-none-any.whl",
                    yanked = None,
                ),
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo==0.0.2",
                    target_platforms = ["linux_x86_64"],
                    filename = "foo-0.0.2-py3-none-any.whl",
                    sha256 = "deadb11f",
                    url = "https://files.pythonhosted.org/packages/foo-0.0.2-py3-none-any.whl",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_uv_lock_primary_source_multiple_versions)

def _test_uv_lock_primary_source_with_extras(env):
    """Test that uv.lock extras are included in requirement lines."""
    got = parse_requirements(
        uv_lock = "uv_lock_foo_with_extras",
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo[extra]==0.0.1",
                    target_platforms = ["linux_x86_64"],
                    filename = "foo-0.0.1-py3-none-any.whl",
                    sha256 = "deadbeef",
                    url = "https://files.pythonhosted.org/packages/foo-0.0.1-py3-none-any.whl",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_uv_lock_primary_source_with_extras)

def _test_uv_lock_primary_source_includes_virtual(env):
    """Test that virtual packages in uv.lock are included."""
    got = parse_requirements(
        uv_lock = "uv_lock_foo_virtual",
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo==0.0.1",
                    target_platforms = ["linux_x86_64"],
                    filename = "foo-0.0.1-py3-none-any.whl",
                    sha256 = "deadbeef",
                    url = "https://files.pythonhosted.org/packages/foo-0.0.1-py3-none-any.whl",
                    yanked = None,
                ),
            ],
        ),
        struct(
            name = "virtual_pkg",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [],
        ),
    ])

_tests.append(_test_uv_lock_primary_source_includes_virtual)

def _test_uv_lock_cross_consistent(env):
    """Test that the uv.lock and requirements work together for cross-platform."""
    got = parse_requirements(
        requirements_by_platform = {
            "requirements_lock": ["linux_x86_64", "windows_x86_64"],
        },
        uv_lock = "uv_lock_foo_with_extras",
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo[extra]==0.0.1",
                    target_platforms = ["linux_x86_64", "windows_x86_64"],
                    filename = "foo-0.0.1-py3-none-any.whl",
                    sha256 = "deadbeef",
                    url = "https://files.pythonhosted.org/packages/foo-0.0.1-py3-none-any.whl",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_uv_lock_cross_consistent)

def _test_uv_lock_vcs_entry(env):
    """Test that VCS entries in uv.lock are handled without crashing."""
    got = parse_requirements(
        uv_lock = "uv_lock_git_vcs",
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo==0.1.0",
                    target_platforms = ["linux_x86_64"],
                    filename = "foo.git",
                    sha256 = "",
                    url = "https://github.com/org/foo.git",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_uv_lock_vcs_entry)

def _test_uv_lock_rules_python_pkg_not_skipped(env):
    """Test that 'rules_python' package is not skipped from uv.lock."""
    got = parse_requirements(
        uv_lock = "uv_lock_rules_python_pkg",
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "rules_python",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "rules_python",
                    extra_pip_args = [],
                    requirement_line = "rules_python==0.0.1",
                    target_platforms = ["linux_x86_64"],
                    filename = "rules_python-0.0.1-py3-none-any.whl",
                    sha256 = "deadbeef",
                    url = "https://files.pythonhosted.org/packages/rules_python-0.0.1-py3-none-any.whl",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_uv_lock_rules_python_pkg_not_skipped)

def _test_uv_lock_no_consistency_check(env):
    """Test that uv.lock is used as the primary source when both uv.lock and requirements exist."""
    got = parse_requirements(
        requirements_by_platform = {
            "requirements_lock": ["linux_x86_64"],
        },
        uv_lock = "uv_lock_foo",
    )

    # The result comes from uv.lock (no extras since uv_lock_foo doesn't have provides-extras)
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo==0.0.1",
                    target_platforms = ["linux_x86_64"],
                    filename = "foo-0.0.1-py3-none-any.whl",
                    sha256 = "deadbeef",
                    url = "https://files.pythonhosted.org/packages/foo-0.0.1-py3-none-any.whl",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_uv_lock_no_consistency_check)

def _test_uv_lock_multiple_packages(env):
    """Test that multiple packages from uv.lock are all returned."""
    got = parse_requirements(
        uv_lock = "uv_lock_foo_bar",
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "bar",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "bar",
                    extra_pip_args = [],
                    requirement_line = "bar==0.0.1",
                    target_platforms = ["linux_x86_64"],
                    filename = "bar-0.0.1.tar.gz",
                    sha256 = "deadb00f",
                    url = "https://files.pythonhosted.org/packages/bar-0.0.1.tar.gz",
                    yanked = None,
                ),
            ],
        ),
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo==0.0.1",
                    target_platforms = ["linux_x86_64"],
                    filename = "foo-0.0.1-py3-none-any.whl",
                    sha256 = "deadbeef",
                    url = "https://files.pythonhosted.org/packages/foo-0.0.1-py3-none-any.whl",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_uv_lock_multiple_packages)

def _test_uv_lock_with_extra_pip_args(env):
    """Test that extra_pip_args are passed through with uv.lock."""
    got = parse_requirements(
        uv_lock = "uv_lock_foo",
        extra_pip_args = ["--index-url=example.org"],
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = ["--index-url=example.org"],
                    requirement_line = "foo==0.0.1",
                    target_platforms = ["linux_x86_64"],
                    filename = "foo-0.0.1-py3-none-any.whl",
                    sha256 = "deadbeef",
                    url = "https://files.pythonhosted.org/packages/foo-0.0.1-py3-none-any.whl",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_uv_lock_with_extra_pip_args)

def _test_uv_lock_multi_os_with_requirements(env):
    """Test that uv.lock works with requirements_by_platform for multi-platform."""
    got = parse_requirements(
        requirements_by_platform = {
            "requirements_foo": ["linux_aarch64"],
            "requirements_lock": ["linux_x86_64", "windows_x86_64"],
        },
        uv_lock = "uv_lock_foo",
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo==0.0.1",
                    target_platforms = ["linux_aarch64", "linux_x86_64", "windows_x86_64"],
                    filename = "foo-0.0.1-py3-none-any.whl",
                    sha256 = "deadbeef",
                    url = "https://files.pythonhosted.org/packages/foo-0.0.1-py3-none-any.whl",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_uv_lock_multi_os_with_requirements)

def _test_uv_lock_extras_optional_deps(env):
    """Test that extras from optional-dependencies in uv.lock are included."""
    got = parse_requirements(
        uv_lock = "uv_lock_foo_optional_deps",
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo[extra1,extra2]==0.0.1",
                    target_platforms = ["linux_x86_64"],
                    filename = "foo-0.0.1-py3-none-any.whl",
                    sha256 = "deadbeef",
                    url = "https://files.pythonhosted.org/packages/foo-0.0.1-py3-none-any.whl",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_uv_lock_extras_optional_deps)

def _test_uv_lock_extras_dep_edge(env):
    """Test that dep extra edges in uv.lock add extras to the dependency."""
    got = parse_requirements(
        uv_lock = "uv_lock_foo_dep_extra",
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "bar",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "bar",
                    extra_pip_args = [],
                    requirement_line = "bar[extra1]==0.0.2",
                    target_platforms = ["linux_x86_64"],
                    filename = "bar-0.0.2-py3-none-any.whl",
                    sha256 = "deadbeef",
                    url = "https://files.pythonhosted.org/packages/bar-0.0.2-py3-none-any.whl",
                    yanked = None,
                ),
            ],
        ),
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo==0.0.1",
                    target_platforms = ["linux_x86_64"],
                    filename = "foo-0.0.1-py3-none-any.whl",
                    sha256 = "baadbeef",
                    url = "https://files.pythonhosted.org/packages/foo-0.0.1-py3-none-any.whl",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_uv_lock_extras_dep_edge)

def _test_uv_lock_wheel_dedup_single_version(env):
    """Test that overlapping wheels for a single version are deduplicated to one per platform."""
    got = parse_requirements(
        uv_lock = "uv_lock_foo_multi_wheel_dedup",
        platforms = {
            "cp39_linux_x86_64": struct(
                env = pep508_env(python_version = "3.9.0", os = "linux", arch = "x86_64"),
                whl_abi_tags = ["none", "abi3", "cp39"],
                whl_platform_tags = ["any", "linux_x86_64", "manylinux_*_x86_64"],
            ),
        },
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo==0.0.1",
                    target_platforms = ["cp39_linux_x86_64"],
                    filename = "foo-0.0.1-cp39-cp39-manylinux_2_17_x86_64.whl",
                    sha256 = "aaa",
                    url = "https://files.pythonhosted.org/packages/foo-0.0.1-cp39-cp39-manylinux_2_17_x86_64.whl",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_uv_lock_wheel_dedup_single_version)

def _test_uv_lock_wheel_dedup_resolution_markers(env):
    """Test that resolution-markers filtering and wheel dedup work together.

    Two versions of foo with resolution-markers for different platforms.
    Each version has a platform-specific wheel and a generic py3-none-any wheel.
    The dedup should pick the platform-specific wheel for each platform and
    the resolution-markers should split versions across platforms.
    """
    got = parse_requirements(
        uv_lock = "uv_lock_foo_resolution_markers_dedup",
        platforms = {
            "cp39_linux_x86_64": struct(
                env = pep508_env(python_version = "3.9.0", os = "linux", arch = "x86_64"),
                whl_abi_tags = ["none", "abi3", "cp39"],
                whl_platform_tags = ["any", "linux_x86_64", "manylinux_*_x86_64"],
            ),
            "cp39_osx_aarch64": struct(
                env = pep508_env(python_version = "3.9.0", os = "osx", arch = "aarch64"),
                whl_abi_tags = ["none", "abi3", "cp39"],
                whl_platform_tags = ["any", "macosx_*_arm64"],
            ),
        },
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = True,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo==0.0.1",
                    target_platforms = ["cp39_linux_x86_64"],
                    filename = "foo-0.0.1-cp39-cp39-manylinux_2_17_x86_64.whl",
                    sha256 = "aaa",
                    url = "https://files.pythonhosted.org/packages/foo-0.0.1-cp39-cp39-manylinux_2_17_x86_64.whl",
                    yanked = None,
                ),
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo==0.0.2",
                    target_platforms = ["cp39_osx_aarch64"],
                    filename = "foo-0.0.2-cp39-cp39-macosx_11_0_arm64.whl",
                    sha256 = "ccc",
                    url = "https://files.pythonhosted.org/packages/foo-0.0.2-cp39-cp39-macosx_11_0_arm64.whl",
                    yanked = None,
                ),
            ],
        ),
    ])

_tests.append(_test_uv_lock_wheel_dedup_resolution_markers)

def _test_uv_lock_requires_dist_extras(env):
    """Test that extras from metadata.requires-dist appear in requirement_line."""
    got = parse_requirements(
        uv_lock = "uv_lock_foo_requires_dist_extras",
    )
    env.expect.that_collection(got).contains_exactly([
        struct(
            name = "foo",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [
                struct(
                    distribution = "foo",
                    extra_pip_args = [],
                    requirement_line = "foo[all]==0.0.1",
                    target_platforms = ["linux_x86_64"],
                    filename = "foo-0.0.1-py3-none-any.whl",
                    sha256 = "deadbeef",
                    url = "https://files.pythonhosted.org/packages/foo-0.0.1-py3-none-any.whl",
                    yanked = None,
                ),
            ],
        ),
        struct(
            name = "root_pkg",
            index_url = "",
            is_exposed = True,
            is_multiple_versions = False,
            srcs = [],
        ),
    ])

_tests.append(_test_uv_lock_requires_dist_extras)

def parse_requirements_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)

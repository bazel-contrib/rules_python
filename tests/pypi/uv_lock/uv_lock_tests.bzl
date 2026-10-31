"""Unit tests for the WORKSPACE uv_lock macro and hub package builder."""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python:pip.bzl", "uv_lock")
load("//python/private/pypi:uv_lock_repo.bzl", "build_uv_lock_hub_packages")  # buildifier: disable=bzl-visibility
load("//tests/support/mocks:mocks.bzl", "mocks")

_tests = []

def _test_single_version(env):
    mock_repo = mocks.repo()

    uv_lock(
        name = "pypi",
        python_interpreter_target = "@python3_14_host//:python",
        uv_lock = "//:uv.lock",
        extra_pip_args = ["--retries=5"],
        _uv_lock_repo = mock_repo.rule,
    )

    env.expect.that_collection(mock_repo.calls).contains_exactly([
        {
            "extra_pip_args": ["--retries=5"],
            "name": "pypi",
            "python_interpreter_target": "@python3_14_host//:python",
            "uv_lock": "//:uv.lock",
        },
    ])

_tests.append(_test_single_version)

def _test_multi_version(env):
    mock_repo = mocks.repo()

    uv_lock(
        name = "pypi",
        default_version = "3.10",
        minor_mapping = {
            "3.10": "3.10.20",
            "3.11": "3.11.15",
        },
        python_interpreter_target = {
            "3.10": "@python_3_10_host//:python",
            "3.11": "@python_3_11_host//:python",
        },
        uv_lock = "//requirements:uv.lock",
        _uv_lock_repo = mock_repo.rule,
    )

    env.expect.that_collection(mock_repo.calls).contains_exactly([
        {
            "default_version": "3.10",
            "minor_mapping": {
                "3.10": "3.10.20",
                "3.11": "3.11.15",
            },
            "name": "pypi",
            "python_interpreter_targets": {
                "3.10": "@python_3_10_host//:python",
                "3.11": "@python_3_11_host//:python",
            },
            "python_versions": ["3.10", "3.11"],
            "uv_lock": "//requirements:uv.lock",
        },
    ])

_tests.append(_test_multi_version)

def _test_build_uv_lock_hub_packages_single_version(env):
    """Verify per-wheel `whl_library` kwargs and hub alias maps in single-version mode."""
    certifi_hex = "035c1e85572b141bf1c3a3eff0e33a8eb74917522f2559075ff8d2fea780a1ae"
    linux_hex = "1111111111111111111111111111111111111111111111111111111111111111"
    osx_hex = "2222222222222222222222222222222222222222222222222222222222222222"
    sdist_hex = "feedcafe0123456789abcdef0123456789abcdef0123456789abcdef01234567"

    version_entry = struct(
        key = "3.11",
        py_nodot = "311",
        full_version = "3.11.14",
        interpreter_target = "@python3_11_host//:python",
    )
    parsed_whls = [
        struct(
            name = "certifi",
            is_exposed = True,
            srcs = [
                struct(
                    distribution = "certifi",
                    extra_pip_args = [],
                    requirement_line = "certifi==2026.10.19",
                    target_platforms = [
                        "linux_aarch64",
                        "linux_x86_64",
                        "osx_aarch64",
                        "osx_x86_64",
                        "windows_x86_64",
                    ],
                    filename = "certifi-2026.10.19-py3-none-any.whl",
                    digest = "sha256:{}".format(certifi_hex),
                    url = "https://files.pythonhosted.org/packages/certifi-2026.10.19-py3-none-any.whl",
                    yanked = None,
                ),
            ],
        ),
        struct(
            name = "charset_normalizer",
            is_exposed = False,
            srcs = [
                struct(
                    distribution = "charset-normalizer",
                    extra_pip_args = [],
                    requirement_line = "charset-normalizer==3.5.2",
                    target_platforms = ["linux_x86_64"],
                    filename = "charset_normalizer-3.5.2-cp37-abi3-manylinux1_x86_64.whl",
                    digest = "sha256:{}".format(linux_hex),
                    url = "https://files.pythonhosted.org/packages/charset_normalizer-3.5.2-cp37-abi3-manylinux1_x86_64.whl",
                    yanked = None,
                ),
                struct(
                    distribution = "charset-normalizer",
                    extra_pip_args = [],
                    requirement_line = "charset-normalizer==3.5.2",
                    target_platforms = ["osx_aarch64", "osx_x86_64"],
                    filename = "charset_normalizer-3.5.2-cp37-abi3-macosx_10_9_universal2.whl",
                    digest = "sha256:{}".format(osx_hex),
                    url = "https://files.pythonhosted.org/packages/charset_normalizer-3.5.2-cp37-abi3-macosx_10_9_universal2.whl",
                    yanked = None,
                ),
            ],
        ),
        struct(
            name = "sdist_only",
            is_exposed = True,
            srcs = [
                struct(
                    distribution = "sdist-only",
                    extra_pip_args = [],
                    requirement_line = "sdist-only==1.0.0",
                    target_platforms = ["linux_x86_64"],
                    filename = "sdist_only-1.0.0.tar.gz",
                    digest = "sha256:{}".format(sdist_hex),
                    url = "https://files.pythonhosted.org/packages/sdist_only-1.0.0.tar.gz",
                    yanked = None,
                ),
            ],
        ),
        struct(
            name = "git_pkg",
            is_exposed = True,
            srcs = [
                struct(
                    distribution = "git-pkg",
                    extra_pip_args = [],
                    requirement_line = "git-pkg @ git+https://github.com/org/repo.git@deadbeef",
                    target_platforms = ["linux_x86_64"],
                    filename = "",
                    digest = "",
                    url = "",
                    yanked = None,
                ),
            ],
        ),
        struct(
            name = "virtual_root",
            is_exposed = False,
            srcs = [],
        ),
    ]

    built = build_uv_lock_hub_packages(
        [(version_entry, parsed_whls)],
        hub_name = "pypi",
        is_multi_version = False,
    )

    env.expect.that_collection(built.bzl_packages).contains_exactly([
        "certifi",
        "git_pkg",
        "sdist_only",
    ])
    env.expect.that_str(built.aliases["certifi"]).equals("pypi_certifi_py3_none_any_035c1e85")
    env.expect.that_dict(built.aliases["charset_normalizer"]).contains_exactly({
        "//_config:is_linux_x86_64": "pypi_charset_normalizer_cp37_abi3_manylinux_2_5_x86_64_11111111",
        "//_config:is_osx_aarch64": "pypi_charset_normalizer_cp37_abi3_macosx_10_9_universal2_22222222",
        "//_config:is_osx_x86_64": "pypi_charset_normalizer_cp37_abi3_macosx_10_9_universal2_22222222",
    })
    env.expect.that_dict(built.packages["pypi_certifi_py3_none_any_035c1e85"]).contains_exactly({
        "filename": "certifi-2026.10.19-py3-none-any.whl",
        "python_interpreter_target": "@python3_11_host//:python",
        "requirement": "certifi==2026.10.19",
        "sha256": certifi_hex,
        "urls": ["https://files.pythonhosted.org/packages/certifi-2026.10.19-py3-none-any.whl"],
    })
    env.expect.that_dict(built.packages["pypi_sdist_only_sdist_feedcafe"]).contains_exactly({
        "python_interpreter_target": "@python3_11_host//:python",
        "requirement": "sdist-only==1.0.0 --hash=sha256:{}".format(sdist_hex),
    })
    env.expect.that_dict(built.packages["pypi_git_pkg"]).contains_exactly({
        "python_interpreter_target": "@python3_11_host//:python",
        "requirement": "git-pkg @ git+https://github.com/org/repo.git@deadbeef",
    })

_tests.append(_test_build_uv_lock_hub_packages_single_version)

def _test_build_uv_lock_hub_packages_multi_version(env):
    """Verify multi-version mode generates per-version spokes and default fallback aliases."""
    whl_hex = "035c1e85572b141bf1c3a3eff0e33a8eb74917522f2559075ff8d2fea780a1ae"
    py310 = struct(
        key = "3.10",
        py_nodot = "310",
        full_version = "3.10.20",
        interpreter_target = "@python_3_10_host//:python",
    )
    py311 = struct(
        key = "3.11",
        py_nodot = "311",
        full_version = "3.11.15",
        interpreter_target = "@python_3_11_host//:python",
    )
    pkg = struct(
        name = "requests",
        is_exposed = True,
        srcs = [
            struct(
                distribution = "requests",
                extra_pip_args = [],
                requirement_line = "requests==2.32.3",
                target_platforms = ["linux_x86_64"],
                filename = "requests-2.32.3-py3-none-any.whl",
                digest = "sha256:{}".format(whl_hex),
                url = "https://files.pythonhosted.org/packages/requests-2.32.3-py3-none-any.whl",
                yanked = None,
            ),
        ],
    )

    built = build_uv_lock_hub_packages(
        [
            (py310, [pkg]),
            (py311, [pkg]),
        ],
        hub_name = "pypi",
        is_multi_version = True,
        default_version = "3.10",
    )

    env.expect.that_dict(built.aliases["requests"]).contains_exactly({
        "//_config:is_cp310_linux_x86_64": "pypi_cp310_requests_py3_none_any_035c1e85",
        "//_config:is_cp311_linux_x86_64": "pypi_cp311_requests_py3_none_any_035c1e85",
        "//_config:is_linux_x86_64": "pypi_cp310_requests_py3_none_any_035c1e85",
    })

_tests.append(_test_build_uv_lock_hub_packages_multi_version)

def uv_lock_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)

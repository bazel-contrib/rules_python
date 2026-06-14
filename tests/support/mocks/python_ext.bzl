"""Helper for defining a mock module for the python bzlmod extension."""

load(":mocks.bzl", "mocks")

def _module(name = "rules_python", is_root = True, **tags):
    """Creates a mock Bzlmod module struct with defaulted tag lists.

    Args:
        name: The module name.
        is_root: Whether this is the root module.
        **tags: Lists of tag objects.

    Returns:
        A mock module struct.
    """
    defaulted_tags = {
        "defaults": [],
        "override": [],
        "single_version_override": [],
        "single_version_platform_override": [],
        "toolchain": [],
    }
    defaulted_tags.update(tags)
    return mocks.module(name = name, is_root = is_root, **defaulted_tags)

def _override(**kwargs):
    """Creates a mock python.override tag with default values."""
    attrs = {
        "add_runtime_manifest_files": [],
        "add_runtime_manifest_urls": [],
        "add_target_settings": [],
        "available_python_versions": [],
        "base_urls": ["https://github.com/astral-sh/python-build-standalone/releases/download"],
        "ignore_root_user_error": True,
        "minor_mapping": {},
        "register_all_versions": False,
        "runtime_manifest_sha": "",
    }
    attrs.update(kwargs)
    return mocks.tag(**attrs)

def _defaults(**kwargs):
    """Creates a mock python.defaults tag with default values."""
    attrs = {
        "python_version": "",
        "python_version_env": "",
    }
    attrs.update(kwargs)
    return mocks.tag(**attrs)

def _single_version_override(**kwargs):
    """Creates a mock python.single_version_override tag with default values."""
    attrs = {
        "distutils": None,
        "distutils_content": "",
        "patch_strip": 0,
        "patches": [],
        "python_version": "",
        "sha256": {},
        "strip_prefix": "python",
        "urls": [],
    }
    attrs.update(kwargs)
    return mocks.tag(**attrs)

def _single_version_platform_override(**kwargs):
    """Creates a mock python.single_version_platform_override tag with default values."""
    attrs = {
        "arch": "",
        "coverage_tool": None,
        "os_name": "",
        "patch_strip": 0,
        "patches": [],
        "platform": "",
        "python_version": "",
        "sha256": "",
        "strip_prefix": "python",
        "target_compatible_with": [],
        "target_settings": [],
        "urls": [],
    }
    attrs.update(kwargs)
    return mocks.tag(**attrs)

def _toolchain(**kwargs):
    """Creates a mock python.toolchain tag with default values."""
    attrs = {
        "configure_coverage_tool": False,
        "ignore_root_user_error": True,
        "is_default": False,
        "python_version": "",
    }
    attrs.update(kwargs)
    return mocks.tag(**attrs)

_DEFAULT_RUNTIMES_MANIFEST = """
87275619c2706affa4d1090d2ca3dad354b6d69f8b85dbfafe38785870751b9a  20251031/cpython-3.9.25+20251031-x86_64-unknown-linux-gnu-install_only.tar.gz
6112d46355857680b81849764a6cf9f38cc4cd0d1cf29d432bc12fe5aeedf9d0  20260414/cpython-3.10.20+20260414-x86_64-unknown-linux-gnu-install_only.tar.gz
1111111111111111111111111111111111111111111111111111111111111111  20241016/cpython-3.10.15+20241016-x86_64-unknown-linux-gnu-install_only.tar.gz
2222222222222222222222222222222222222222222222222222222222222222  20240224/cpython-3.10.13+20240224-x86_64-unknown-linux-gnu-install_only.tar.gz
0000000000000000000000000000000000000000000000000000000000000000  20260414/cpython-3.11.15+20260414-x86_64-unknown-linux-gnu-install_only.tar.gz
3333333333333333333333333333333333333333333333333333333333333333  20241016/cpython-3.11.10+20241016-x86_64-unknown-linux-gnu-install_only.tar.gz
4444444444444444444444444444444444444444444444444444444444444444  20230116/cpython-3.11.2+20230116-x86_64-unknown-linux-gnu-install_only.tar.gz
5555555555555555555555555555555555555555555555555555555555555555  20230116/cpython-3.11.1+20230116-x86_64-unknown-linux-gnu-install_only.tar.gz
6666666666666666666666666666666666666666666666666666666666666666  20260414/cpython-3.12.13+20260414-x86_64-unknown-linux-gnu-install_only.tar.gz
7777777777777777777777777777777777777777777777777777777777777777  20240726/cpython-3.12.4+20240726-x86_64-unknown-linux-gnu-install_only.tar.gz
8888888888888888888888888888888888888888888888888888888888888888  20260414/cpython-3.13.13+20260414-x86_64-unknown-linux-gnu-install_only.tar.gz
9999999999999999999999999999999999999999999999999999999999999999  20241016/cpython-3.13.0+20241016-x86_64-unknown-linux-gnu-install_only.tar.gz
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  20260414/cpython-3.14.4+20260414-x86_64-unknown-linux-gnu-install_only.tar.gz
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  20251031/cpython-3.14.0+20251031-x86_64-unknown-linux-gnu-install_only.tar.gz
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc  20260414/cpython-3.15.0a8+20260414-x86_64-unknown-linux-gnu-install_only.tar.gz
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd  20241205/cpython-3.13.1+20241205-x86_64-unknown-linux-gnu-install_only.tar.gz
"""

def _mctx(*args, **kwargs):
    """Creates a mock module_ctx pre-populated with the default runtimes manifest.

    Args:
        *args: Positional arguments to pass to mocks.mctx.
        **kwargs: Keyword arguments to pass to mocks.mctx.

    Returns:
        A mock module_ctx struct.
    """
    mock_files = {
        "python/private/runtimes_manifest.txt": _DEFAULT_RUNTIMES_MANIFEST,
    }
    mock_files.update(kwargs.pop("mock_files", {}))
    kwargs["mock_files"] = mock_files
    return mocks.mctx(*args, **kwargs)

python_ext = struct(
    defaults = _defaults,
    mctx = _mctx,
    module = _module,
    override = _override,
    single_version_override = _single_version_override,
    single_version_platform_override = _single_version_platform_override,
    toolchain = _toolchain,
)

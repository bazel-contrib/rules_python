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
        "add_runtime_manifest_urls": [],
        "add_target_settings": [],
        "available_python_versions": [],
        "base_url": "https://github.com/astral-sh/python-build-standalone/releases/download",
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

python_ext = struct(
    defaults = _defaults,
    module = _module,
    override = _override,
    single_version_override = _single_version_override,
    single_version_platform_override = _single_version_platform_override,
    toolchain = _toolchain,
)

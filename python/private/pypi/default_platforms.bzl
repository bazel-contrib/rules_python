"""The default platforms used for selecting the wheels."""

def default_platforms():
    """Return the built-in default platform definitions.

    These provide the platform metadata needed for pip wheel resolution
    (whl_abi_tags, whl_platform_tags, config_settings, etc.) across all
    common OS/arch combinations. They are always used as the starting point
    for build_config; root modules can override individual platforms via
    pip.default tags.

    Returns:
        A dict of platform name to platform config dicts.
    """
    # NOTE @aignas 2025-07-06: we define these platforms to keep backwards compatibility. Whilst we
    # stabilize the API this list may be updated with a mention in the CHANGELOG.

    platforms = {}

    # Linux platforms
    for cpu in ["x86_64", "aarch64"]:
        for freethreaded in ["", "_freethreaded"]:
            platform_name = "linux_{}{}".format(cpu, freethreaded)
            platforms[platform_name] = {
                "arch_name": cpu,
                "config_settings": [
                    "@platforms//cpu:{}".format(cpu),
                    "@platforms//os:linux",
                    "//python/config_settings:_is_py_freethreaded_{}".format(
                        "yes" if freethreaded else "no",
                    ),
                ],
                "env": {"platform_version": "0"},
                "marker": "python_version >= '3.13'" if freethreaded else "",
                "name": platform_name,
                "os_name": "linux",
                "whl_abi_tags": ["cp{major}{minor}t"] if freethreaded else [
                    "abi3",
                    "cp{major}{minor}",
                ],
                "whl_platform_tags": [
                    "linux_{}".format(cpu),
                    "manylinux_*_{}".format(cpu),
                ],
            }

    # macOS platforms
    for cpu, platform_tag_cpus in {
        "aarch64": ["universal2", "arm64"],
        "x86_64": ["universal2", "x86_64"],
    }.items():
        for freethreaded in ["", "_freethreaded"]:
            platform_name = "osx_{}{}".format(cpu, freethreaded)
            platforms[platform_name] = {
                "arch_name": cpu,
                "config_settings": [
                    "@platforms//cpu:{}".format(cpu),
                    "@platforms//os:osx",
                    "//python/config_settings:_is_py_freethreaded_{}".format(
                        "yes" if freethreaded else "no",
                    ),
                ],
                "env": {"platform_version": "14.0"},
                "marker": "python_version >= '3.13'" if freethreaded else "",
                "name": platform_name,
                "os_name": "osx",
                "whl_abi_tags": ["cp{major}{minor}t"] if freethreaded else [
                    "abi3",
                    "cp{major}{minor}",
                ],
                "whl_platform_tags": [
                    "macosx_*_{}".format(suffix)
                    for suffix in platform_tag_cpus
                ],
            }

    # Windows x86_64 platforms
    for freethreaded in ["", "_freethreaded"]:
        platform_name = "windows_x86_64{}".format(freethreaded)
        platforms[platform_name] = {
            "arch_name": "x86_64",
            "config_settings": [
                "@platforms//cpu:x86_64",
                "@platforms//os:windows",
                "//python/config_settings:_is_py_freethreaded_{}".format(
                    "yes" if freethreaded else "no",
                ),
            ],
            "env": {"platform_version": "0"},
            "marker": "python_version >= '3.13'" if freethreaded else "",
            "name": platform_name,
            "os_name": "windows",
            "whl_abi_tags": ["cp{major}{minor}t"] if freethreaded else [
                "abi3",
                "cp{major}{minor}",
            ],
            "whl_platform_tags": ["win_amd64"],
        }

    # Windows aarch64 platforms
    for freethreaded in ["", "_freethreaded"]:
        platform_name = "windows_aarch64{}".format(freethreaded)
        platforms[platform_name] = {
            "arch_name": "aarch64",
            "config_settings": [
                "@platforms//cpu:aarch64",
                "@platforms//os:windows",
                "//python/config_settings:_is_py_freethreaded_{}".format(
                    "yes" if freethreaded else "no",
                ),
            ],
            "env": {"platform_version": "0"},
            "marker": "python_version >= '3.13'" if freethreaded else "python_version >= '3.11'",
            "name": platform_name,
            "os_name": "windows",
            "whl_abi_tags": ["cp{major}{minor}t"] if freethreaded else [
                "abi3",
                "cp{major}{minor}",
            ],
            "whl_platform_tags": ["win_arm64"],
        }

    return platforms

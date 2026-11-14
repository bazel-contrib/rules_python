"""The default platforms used for selecting the wheels."""

def _platform(
        *,
        name,
        os_name,
        arch_name,
        cpu,
        whl_platform_tags,
        platform_version,
        freethreaded,
        os_constraint = None,
        config_settings = [],
        marker = ""):
    return {
        "arch_name": arch_name,
        "config_settings": [
            "@platforms//cpu:{}".format(cpu),
            "@platforms//os:{}".format(os_constraint or os_name),
        ] + config_settings + [
            "//python/config_settings:_is_py_freethreaded_{}".format(
                "yes" if freethreaded else "no",
            ),
        ],
        "env": {"platform_version": platform_version},
        "marker": "python_version >= '3.13'" if freethreaded else marker,
        "name": name,
        "os_name": os_name,
        # The free-threaded builds can use the `abi3t` stable ABI wheels, see
        # https://peps.python.org/pep-0803/. The python tag of the `abi3t` wheels
        # is the minimum supported version, which is handled in the same way as
        # for `abi3` when selecting the wheels. The GIL-enabled builds cannot
        # use `abi3t` wheels unless they are also tagged with `abi3`, e.g.
        # `cp315-abi3.abi3t`.
        #
        # The last item has the highest priority.
        "whl_abi_tags": ["abi3t", "cp{major}{minor}t"] if freethreaded else [
            "abi3",
            "cp{major}{minor}",
        ],
        "whl_platform_tags": whl_platform_tags,
    }

def default_platforms():
    """Return the built-in default platform definitions.

    These provide the platform metadata needed for pip wheel resolution
    (whl_abi_tags, whl_platform_tags, config_settings, etc.) across all
    common OS/arch combinations. They are always used as the starting point
    for build_config; root modules can override individual platforms via
    pip.default tags.

    There is a platform for each of the platforms that the hermetic Python
    toolchains support, see `//python:versions.bzl`.

    Returns:
        A dict of platform name to platform config dicts.
    """
    # NOTE @aignas 2025-07-06: we define these platforms to keep backwards compatibility. Whilst we
    # stabilize the API this list may be updated with a mention in the CHANGELOG.

    platforms = {}
    for freethreaded in ["", "_freethreaded"]:
        # Linux glibc platforms. The key is the platform name suffix and the
        # values are the `@platforms//cpu` constraint, the `arch_name` and the
        # wheel platform tag suffix.
        for name, (cpu, arch_name, tag) in {
            "aarch64": ("aarch64", "aarch64", "aarch64"),
            "armv7": ("armv7", "arm", "armv7l"),
            "i386": ("i386", "x86_32", "i686"),
            "ppc": ("ppc", "ppc", "ppc64le"),
            "riscv64": ("riscv64", "riscv64", "riscv64"),
            "s390x": ("s390x", "s390x", "s390x"),
            "x86_64": ("x86_64", "x86_64", "x86_64"),
        }.items():
            platform_name = "linux_{}{}".format(name, freethreaded)
            platforms[platform_name] = _platform(
                name = platform_name,
                os_name = "linux",
                arch_name = arch_name,
                cpu = cpu,
                config_settings = [
                    "//python/config_settings:_is_py_linux_libc_glibc",
                ],
                platform_version = "0",
                freethreaded = freethreaded,
                whl_platform_tags = [
                    "linux_{}".format(tag),
                    "manylinux_*_{}".format(tag),
                ],
            )

        # Linux musl platforms
        platform_name = "linux_x86_64_musl{}".format(freethreaded)
        platforms[platform_name] = _platform(
            name = platform_name,
            os_name = "linux",
            arch_name = "x86_64",
            cpu = "x86_64",
            config_settings = [
                "//python/config_settings:_is_py_linux_libc_musl",
            ],
            platform_version = "0",
            freethreaded = freethreaded,
            whl_platform_tags = ["musllinux_*_x86_64"],
        )

        # macOS platforms
        for cpu, platform_tag_cpus in {
            "aarch64": ["universal2", "arm64"],
            "arm64e": ["arm64e"],
            "x86_64": ["universal2", "x86_64"],
        }.items():
            platform_name = "osx_{}{}".format(cpu, freethreaded)
            platforms[platform_name] = _platform(
                name = platform_name,
                os_name = "osx",
                arch_name = "aarch64" if cpu == "arm64e" else cpu,
                cpu = cpu,
                platform_version = "14.0",
                freethreaded = freethreaded,
                whl_platform_tags = [
                    "macosx_*_{}".format(suffix)
                    for suffix in platform_tag_cpus
                ],
            )

        # Windows platforms
        for cpu, (tag, marker) in {
            "aarch64": ("win_arm64", "python_version >= '3.11'"),
            "x86_32": ("win32", ""),
            "x86_64": ("win_amd64", ""),
        }.items():
            platform_name = "windows_{}{}".format(cpu, freethreaded)
            platforms[platform_name] = _platform(
                name = platform_name,
                os_name = "windows",
                arch_name = cpu,
                cpu = cpu,
                platform_version = "0",
                freethreaded = freethreaded,
                marker = marker,
                whl_platform_tags = [tag],
            )

    return platforms

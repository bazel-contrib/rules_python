"""Create the `select_whl` target platform for a hermetic python toolchain."""

load("//python:versions.bzl", "FREETHREADED")
load("//python/private:version.bzl", "version")
load(":pep508_env.bzl", "env")
load(":platform.bzl", "platform")

# The CPU part of the toolchain platform triple to the `platform_machine` like
# value used in the wheel platform tags. If a CPU is not listed here, then only
# the platform independent wheels can be used.
_LINUX_CPUS = {
    "aarch64": "aarch64",
    "armv7": "armv7l",
    "i386": "i686",
    "ppc64le": "ppc64le",
    "riscv64": "riscv64",
    "s390x": "s390x",
    "x86_64": "x86_64",
}

# NOTE: `arm64e` is not listed because the `arm64` wheels may not be loadable
# by an `arm64e` interpreter.
_MACOS_CPUS = {
    "aarch64": "arm64",
    "x86_64": "x86_64",
}

# The `@platforms//cpu` values used in the PEP508 env.
_PLATFORMS_CPUS = {
    "arm64e": "aarch64",
    "armv7": "armv7",
    "i386": "x86_32",
    "ppc64le": "ppc64le",
}

def python_toolchain_platform(*, python_version, platform_name):
    """Create the target platform for selecting wheels for a python toolchain.

    The returned value can be used to call `select_whl` and to evaluate the
    PEP508 markers for the given python toolchain.

    Args:
        python_version: {type}`str` the full python version of the toolchain,
            e.g. `3.13.1`.
        platform_name: {type}`str` the python toolchain platform, i.e. one of
            the keys in the `PLATFORMS` dict in `//python:versions.bzl` without
            the distribution suffix, e.g. `x86_64-unknown-linux-gnu` or
            `aarch64-apple-darwin-freethreaded`.

    Returns:
        A struct returned by `platform()` from `//python/private/pypi:platform.bzl`
        with the `env`, `whl_abi_tags` and `whl_platform_tags` populated for
        the given python version and platform.
    """
    triple = platform_name.removesuffix(FREETHREADED)
    freethreaded = triple != platform_name
    cpu, _, tail = triple.partition("-")

    if tail == "apple-darwin":
        os_name = "osx"
        machine = _MACOS_CPUS.get(cpu)
        whl_platform_tags = []
        if machine:
            whl_platform_tags = [
                "macosx_*_universal2",
                "macosx_*_{}".format(machine),
            ]
    elif tail.endswith("-linux-gnu"):
        os_name = "linux"
        machine = _LINUX_CPUS.get(cpu)
        whl_platform_tags = []
        if machine:
            whl_platform_tags = ["manylinux_*_{}".format(machine)]
    elif tail.endswith("-linux-musl"):
        os_name = "linux"
        machine = _LINUX_CPUS.get(cpu)
        whl_platform_tags = []
        if machine:
            whl_platform_tags = ["musllinux_*_{}".format(machine)]
    else:
        fail("Unsupported python toolchain platform: '{}'".format(platform_name))

    v = version.parse(python_version, strict = True)
    abi = "cp{}{}".format(v.release[0], v.release[1])
    whl_abi_tags = [abi + "t"] if freethreaded else ["abi3", abi]

    arch = _PLATFORMS_CPUS.get(cpu, cpu)
    return platform(
        name = platform_name,
        arch_name = arch,
        os_name = os_name,
        env = env(
            os = os_name,
            arch = arch,
            python_version = python_version,
        ),
        whl_abi_tags = whl_abi_tags,
        whl_platform_tags = whl_platform_tags,
    )

# Copyright 2022 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""The Python versions we use for the toolchains.
"""

load("//python/private:platform_info.bzl", "platform_info")

# Values present in the @platforms//os package
MACOS_NAME = "osx"
LINUX_NAME = "linux"
WINDOWS_NAME = "windows"

FREETHREADED = "-freethreaded"
MUSL = "-musl"
INSTALL_ONLY = "install_only"

DEFAULT_RELEASE_BASE_URL = "https://github.com/astral-sh/python-build-standalone/releases/download"

# When updating the versions and releases, run the following command to get
# the hashes:
#   bazel run //python/private:print_toolchains_checksums --//python/config_settings:python_version={major}.{minor}.{patch}
#
# Note, to users looking at how to specify their tool versions, coverage_tool version for each
# interpreter can be specified by:
#   "3.8.10": {
#       "url": "20210506/cpython-{python_version}-{platform}-pgo+lto-20210506T0943.tar.zst",
#       "sha256": {
#           "x86_64-apple-darwin": "8d06bec08db8cdd0f64f4f05ee892cf2fcbc58cfb1dd69da2caab78fac420238",
#           "x86_64-unknown-linux-gnu": "aec8c4c53373b90be7e2131093caa26063be6d9d826f599c935c0e1042af3355",
#       },
#       "coverage_tool": {
#           "x86_64-apple-darwin": "<label_for_darwin>"",
#           "x86_64-unknown-linux-gnu": "<label_for_linux>"",
#       },
#       "strip_prefix": "python",
#   },
#
# It is possible to provide lists in "url". It is also possible to provide patches or patch_strip.
#
# NOTE: in order to get sha256 values for all of the versions used below, run the following snippet:
#   for minor in 9 10 11 12 13 14; do
#       bazel run //python/private:print_toolchains_checksums --//python/config_settings:python_version=3.$minor
#   done
#
# buildifier: disable=unsorted-dict-items
TOOL_VERSIONS = {
    "3.8.20": {
        "url": "20241002/cpython-{python_version}+20241002-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "2ddfc04bdb3e240f30fb782fa1deec6323799d0e857e0b63fa299218658fd3d4",
            "aarch64-unknown-linux-gnu": "9d8798f9e79e0fc0f36fcb95bfa28a1023407d51a8ea5944b4da711f1f75f1ed",
            "x86_64-apple-darwin": "68d060cd373255d2ca5b8b3441363d5aa7cc45b0c11bbccf52b1717c2b5aa8bb",
            "x86_64-pc-windows-msvc": "41b6709fec9c56419b7de1940d1f87fa62045aff81734480672dcb807eedc47e",
            "x86_64-unknown-linux-gnu": "285e141c36f88b2e9357654c5f77d1f8fb29cc25132698fe35bb30d787f38e87",
        },
        "strip_prefix": "python",
    },
    "3.9.23": {
        "url": "20250626/cpython-{python_version}+20250626-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "04337413914bda368c7087d28ea76cd7ba1185b8f367298a1026d14b898ffcb9",
            "aarch64-unknown-linux-gnu": "ba3a45fd82b4c2fa8ef3e29a9d6be58000ca710de08cb59a225e8ff4c14b5298",
            "ppc64le-unknown-linux-gnu": "d7fe4a9f2bd8b78b9c8769dc2b84bdbd3a54ea0dd286e758695edebece51a9c5",
            "riscv64-unknown-linux-gnu": "833cdd6756d37d00f3f40256ae95050f3f5ce9aac984721403f34602b6762036",
            "s390x-unknown-linux-gnu": "7a10cc62d398f741d1b020dcfb3806a85325cfcceb1b02d205023d8ca4793d05",
            "x86_64-apple-darwin": "439f067760ab17274c1b3983e24b4d31675b8d4b4653a864688497b67a8e596b",
            "x86_64-pc-windows-msvc": "413a85ad392d3de68f4865f38e91d0e3ba49dffa5ddce57a0aee9fce0bc3bedb",
            "x86_64-unknown-linux-gnu": "f9c1835ca8f0d9947d0d6646b737b91368f999d67ebd738dc2958b6e323f799f",
            "x86_64-unknown-linux-musl": "f9ed35e6248d69ba8b93fc7fde319cb54e499afa9a7a3b36b954a08b5e31f38a",
        },
        "strip_prefix": "python",
    },
    "3.10.18": {
        "url": "20250626/cpython-{python_version}+20250626-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "2ee23be65e4512cf9c03eada2c26c84fc8af3fe2930436ea8174757a20ab6e01",
            "aarch64-unknown-linux-gnu": "aa8028c5290167769e604d10142e0d80feeb0689029da9659a6a75da0dfcbc4a",
            "ppc64le-unknown-linux-gnu": "805ef7c084a4fbc362639fdab40c6ec94ef91ff940781be9a162146972fe7583",
            "riscv64-unknown-linux-gnu": "b6167452b8a0a64421765bb9d45b03e08bbaed7d085597083dba711688c12f27",
            "s390x-unknown-linux-gnu": "8b04aefa12db1592fc4d612c2d75b4def67632d067ec36e86c6f134822b4f42f",
            "x86_64-apple-darwin": "11d8a8b15b954ae3d232b0c7b10cb9f33f4cfa71afc09a86df46303bed86cc90",
            "x86_64-pc-windows-msvc": "b294e565008d3b1e4c773613fc6e5f8f858c834228059b1dc5de9e2332a88338",
            "x86_64-unknown-linux-gnu": "b3085609d06eda0bdda3f95f084e611e845f973dfc10480a71ad8a067c3eaeb5",
            "x86_64-unknown-linux-musl": "9538bd032b410cc99f7af329c0fe49af7cba8c4625f499c089412b98b825bb2a",
        },
        "strip_prefix": "python",
    },
    "3.11.13": {
        "url": "20250626/cpython-{python_version}+20250626-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "fd3bc3b011b49fc66ccc85099c7ec646242f5802f7759e5c26f06a9d41476ae2",
            "aarch64-unknown-linux-gnu": "7b65d27357f3101576e6a30ebfd1462d794a02be2c2068abfb147480a8a494df",
            "ppc64le-unknown-linux-gnu": "5aaed1e8fc99884024d4d776f8dd8d6bc1eb625d004f19f62f099c0f968bbd7a",
            "riscv64-unknown-linux-gnu": "4649a22bda44f282366cc09c6b1e7bfcb83b3b69ff8ba73535faf2632c0428d9",
            "s390x-unknown-linux-gnu": "10c480e5d9fc7573bbad3c99c71bbbab159199efe69901f32bb10736a16c82a1",
            "x86_64-apple-darwin": "82a709c1d8220f26a0d3b35a566047e1fed0a41d39013953720ce92dac527a3d",
            "x86_64-pc-windows-msvc": "5cf5f87a9131e179007ca830e862d034c30759d07d0d8f92fc552593247a43f2",
            "x86_64-unknown-linux-gnu": "3bf2066dd96c86aacfd2b016699667e2a0bcb97ec63fb7791e230c7deda0a90f",
            "x86_64-unknown-linux-musl": "aef2cbee62dcec7cbf9047555cefdc5859ea6ab822fdc9c300c3c8e5b9aef719",
        },
        "strip_prefix": "python",
    },
    "3.12.11": {
        "url": "20250626/cpython-{python_version}+20250626-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "47a3ba9baaa2f75389a0374c615fa6402815d512a7c583c52db3554e6892aa4e",
            "aarch64-unknown-linux-gnu": "d0367c2310f6a12aa13d8b4a1d378aba9f6813d941339173a2c89a6d30c5829b",
            "ppc64le-unknown-linux-gnu": "9c86330d3d2d7fc99eea6723460727d8d54de572eb7abbbb4aa54ccca87c0ad8",
            "riscv64-unknown-linux-gnu": "4458500e9466e4cd0aadd26f83ec2161738c73240e4caa16e5cb4c10ff871e8e",
            "s390x-unknown-linux-gnu": "e416b65879c7578eba9bc58ad1405bd3dc4c5fd181a334c7a8d85fc7c40c1bf2",
            "x86_64-apple-darwin": "e1f19f8246d01e8e048c89fef8b739768db16dc15559256ce70c1a37ace7243f",
            "x86_64-pc-windows-msvc": "36c5db0f7cf0340286fe322795cb0ee80fd92443851f8ccf8a87720a767178c7",
            "x86_64-unknown-linux-gnu": "b6c54f06dc4af6f7ffe007844914737dbe1f95cb45ce2bcc84b5ca0697e4f320",
            "x86_64-unknown-linux-musl": "e2c9ab2ab590cd549d7a6a5d6db6b4db81e95090ab1ea5cde76e1a2e8174a1ba",
        },
        "strip_prefix": "python",
    },
    "3.13.5": {
        "url": "20250626/cpython-{python_version}+20250626-{platform}-{build}.{ext}",
        "sha256": {
            "aarch64-apple-darwin": "1aed085640a388ff979e705e827277f69e8b78048df5f7bffdde09b92ada6049",
            "aarch64-unknown-linux-gnu": "f96a811e90a26b95520f135fa55594c22954602cc59ebd7967b1c3c68e42511d",
            "ppc64le-unknown-linux-gnu": "440ff2c92999d799e6df060ac5ae8e3c139aabf6704cf3aae8c60c3954e03d60",
            "riscv64-unknown-linux-gnu": "9d94c7046add9c7b94ef0a69c8e1018a27b47dc5da7dbe5797e50e4b17ff9a10",
            "s390x-unknown-linux-gnu": "780fdb2622c9a12446a3fd43c9b46db8425eb44875efadfab7965dea938b2623",
            "x86_64-apple-darwin": "f0ae8a9da4f3cf12a7f1435517309d9a75e819a475064d92dc39c7b21b1ee299",
            "x86_64-pc-windows-msvc": "e8964d26fa4678bfec69a6cfbe1eb37c703bc3799167c57a6e25f66719ded19c",
            "x86_64-unknown-linux-gnu": "b92b2f88740c9889232bbbde9a98d3e6edd4cab1eb85fdc6ec5929516bd140e5",
            "x86_64-unknown-linux-musl": "cd0d21ad885fd68168c4111c976ed2a43aee1a258e17e7e4183af9ce67a49c9b",
            "aarch64-apple-darwin-freethreaded": "7223a0e13d5e290fa8441b5439d08fca6fe389bcc186f918f2edd808027dcd08",
            "aarch64-unknown-linux-gnu-freethreaded": "8437225a6066e9f57a2ce631a73eceedffeadfe4146b7861e6ace5647a0472da",
            "ppc64le-unknown-linux-gnu-freethreaded": "09008067d69b833b831cc6090edb221f1cce780c4586db8231dcfb988d1b7571",
            "riscv64-unknown-linux-gnu-freethreaded": "3bc92a4057557e9a9f7e8bd8e673dfae54f9abbd14217ae4d986ba29c8c1e761",
            "s390x-unknown-linux-gnu-freethreaded": "3206aa76d604d87222ef1cd069b4c7428b3a8f991580504ae21f0926c53a97c5",
            "x86_64-apple-darwin-freethreaded": "869ca9d095f9e8f50fc8609d55d6a937c48a7d0b09e7ab5a3679307f9eb90c70",
            "x86_64-pc-windows-msvc-freethreaded": "79c5594d758c7db8323abc23325e17955a6c6e300fec04abdeecf29632de1e34",
            "x86_64-unknown-linux-gnu-freethreaded": "a45ffc5a812c3b6db1dce34fc72c35fb3c791075c4602d0fb742c889bc6bf26d",
        },
        "strip_prefix": {
            "aarch64-apple-darwin": "python",
            "aarch64-unknown-linux-gnu": "python",
            "ppc64le-unknown-linux-gnu": "python",
            "s390x-unknown-linux-gnu": "python",
            "riscv64-unknown-linux-gnu": "python",
            "x86_64-apple-darwin": "python",
            "x86_64-pc-windows-msvc": "python",
            "x86_64-unknown-linux-gnu": "python",
            "x86_64-unknown-linux-musl": "python",
            "aarch64-apple-darwin-freethreaded": "python/install",
            "aarch64-unknown-linux-gnu-freethreaded": "python/install",
            "ppc64le-unknown-linux-gnu-freethreaded": "python/install",
            "riscv64-unknown-linux-gnu-freethreaded": "python/install",
            "s390x-unknown-linux-gnu-freethreaded": "python/install",
            "x86_64-apple-darwin-freethreaded": "python/install",
            "x86_64-pc-windows-msvc-freethreaded": "python/install",
            "x86_64-unknown-linux-gnu-freethreaded": "python/install",
        },
    },
    "3.14.0b3": {
        "url": "20250626/cpython-{python_version}+20250626-{platform}-{build}.{ext}",
        "sha256": {
            "aarch64-apple-darwin": "40e9e524a6b3222178fdb9b18b59169db796408da70fa78af575875283d80164",
            "aarch64-unknown-linux-gnu": "3bae796f8c398a1db0068e03d7569bb6fe2d8ef032b90b3a0f8a419de977d24e",
            "ppc64le-unknown-linux-gnu": "4ab6708dc06300adfc45c10ad3ecafaf1149ff3bd84ecc73719411f8ba4c0709",
            "riscv64-unknown-linux-gnu": "1d0ee1961cc461b37bb2b9bab1d07e4b2a16981cc3300decbe77fbd5274d298b",
            "s390x-unknown-linux-gnu": "27f26cfffdfe56c6e238f781ef5283f7393e536ab20d62c6ebd51a61a070c383",
            "x86_64-apple-darwin": "735d1141aab13c81b858d5b2dccef585ff175e6292ab67771adabcd0415704e8",
            "x86_64-pc-windows-msvc": "e52717dd62c1b62e65b9a7cbec4d5fec87d7c865a29c3946c5bd380af400013a",
            "x86_64-unknown-linux-gnu": "17c6ac4cda099e53f2ee17683378733c82f191bd72a9a8d3d8f236c158c3b1fb",
            "x86_64-unknown-linux-musl": "4603033952bdbc513222c2032da19ef07c362088cddffa111013c1cc11954550",
            "aarch64-apple-darwin-freethreaded": "0ad27d76b4a5ebe3fac67bf928ea07bea5335fe6f0f33880277db73640a96df1",
            "aarch64-unknown-linux-gnu-freethreaded": "15abb894679fafa47e71b37fb722de526cad5a55b42998d9ba7201023299631b",
            "ppc64le-unknown-linux-gnu-freethreaded": "2127b36c4b16da76a713fb4c2e8a6a2757a6d73a07a6ee4fa14d2a02633e0605",
            "riscv64-unknown-linux-gnu-freethreaded": "dca86f8df4d6a65a69e8deb65e60ed0b27a376f2d677ec9150138d4e3601f4f7",
            "s390x-unknown-linux-gnu-freethreaded": "5f119f34846d6f150c8de3b8ce81418f5cf60f90b51fcc594cb54d6ab4db030d",
            "x86_64-apple-darwin-freethreaded": "26e5c3e51de17455ed4c7f2b81702b175cf230728e4fdd93b3c426d21df09df2",
            "x86_64-pc-windows-msvc-freethreaded": "5c864084d8b8d5b5e9d4d5005f92ec2f7bdb65c13bc9b95a9ac52b2bcb4db8e0",
            "x86_64-unknown-linux-gnu-freethreaded": "ac5373d3b945298f34f1ebd5b03ce35ce92165638443ef65f8ca2d2eba07e39d",
        },
        "strip_prefix": {
            "aarch64-apple-darwin": "python",
            "aarch64-unknown-linux-gnu": "python",
            "ppc64le-unknown-linux-gnu": "python",
            "s390x-unknown-linux-gnu": "python",
            "riscv64-unknown-linux-gnu": "python",
            "x86_64-apple-darwin": "python",
            "x86_64-pc-windows-msvc": "python",
            "x86_64-unknown-linux-gnu": "python",
            "x86_64-unknown-linux-musl": "python",
            "aarch64-apple-darwin-freethreaded": "python/install",
            "aarch64-unknown-linux-gnu-freethreaded": "python/install",
            "ppc64le-unknown-linux-gnu-freethreaded": "python/install",
            "riscv64-unknown-linux-gnu-freethreaded": "python/install",
            "s390x-unknown-linux-gnu-freethreaded": "python/install",
            "x86_64-apple-darwin-freethreaded": "python/install",
            "x86_64-pc-windows-msvc-freethreaded": "python/install",
            "x86_64-unknown-linux-gnu-freethreaded": "python/install",
        },
    },
}

# buildifier: disable=unsorted-dict-items
MINOR_MAPPING = {
    "3.8": "3.8.20",
    "3.9": "3.9.23",
    "3.10": "3.10.18",
    "3.11": "3.11.13",
    "3.12": "3.12.11",
    "3.13": "3.13.5",
    "3.14": "3.14.0b3",
}

def _generate_platforms():
    is_libc_glibc = str(Label("//python/config_settings:_is_py_linux_libc_glibc"))
    is_libc_musl = str(Label("//python/config_settings:_is_py_linux_libc_musl"))

    platforms = {
        "aarch64-apple-darwin": platform_info(
            compatible_with = [
                "@platforms//os:macos",
                "@platforms//cpu:aarch64",
            ],
            os_name = MACOS_NAME,
            arch = "aarch64",
        ),
        "aarch64-unknown-linux-gnu": platform_info(
            compatible_with = [
                "@platforms//os:linux",
                "@platforms//cpu:aarch64",
            ],
            target_settings = [
                is_libc_glibc,
            ],
            os_name = LINUX_NAME,
            arch = "aarch64",
        ),
        "armv7-unknown-linux-gnu": platform_info(
            compatible_with = [
                "@platforms//os:linux",
                "@platforms//cpu:armv7",
            ],
            target_settings = [
                is_libc_glibc,
            ],
            os_name = LINUX_NAME,
            arch = "arm",
        ),
        "i386-unknown-linux-gnu": platform_info(
            compatible_with = [
                "@platforms//os:linux",
                "@platforms//cpu:i386",
            ],
            target_settings = [
                is_libc_glibc,
            ],
            os_name = LINUX_NAME,
            arch = "x86_32",
        ),
        "ppc64le-unknown-linux-gnu": platform_info(
            compatible_with = [
                "@platforms//os:linux",
                "@platforms//cpu:ppc",
            ],
            target_settings = [
                is_libc_glibc,
            ],
            os_name = LINUX_NAME,
            arch = "ppc",
        ),
        "riscv64-unknown-linux-gnu": platform_info(
            compatible_with = [
                "@platforms//os:linux",
                "@platforms//cpu:riscv64",
            ],
            target_settings = [
                is_libc_glibc,
            ],
            os_name = LINUX_NAME,
            arch = "riscv64",
        ),
        "s390x-unknown-linux-gnu": platform_info(
            compatible_with = [
                "@platforms//os:linux",
                "@platforms//cpu:s390x",
            ],
            target_settings = [
                is_libc_glibc,
            ],
            os_name = LINUX_NAME,
            arch = "s390x",
        ),
        "x86_64-apple-darwin": platform_info(
            compatible_with = [
                "@platforms//os:macos",
                "@platforms//cpu:x86_64",
            ],
            os_name = MACOS_NAME,
            arch = "x86_64",
        ),
        "x86_64-pc-windows-msvc": platform_info(
            compatible_with = [
                "@platforms//os:windows",
                "@platforms//cpu:x86_64",
            ],
            os_name = WINDOWS_NAME,
            arch = "x86_64",
        ),
        "x86_64-unknown-linux-gnu": platform_info(
            compatible_with = [
                "@platforms//os:linux",
                "@platforms//cpu:x86_64",
            ],
            target_settings = [
                is_libc_glibc,
            ],
            os_name = LINUX_NAME,
            arch = "x86_64",
        ),
        "x86_64-unknown-linux-musl": platform_info(
            compatible_with = [
                "@platforms//os:linux",
                "@platforms//cpu:x86_64",
            ],
            target_settings = [
                is_libc_musl,
            ],
            os_name = LINUX_NAME,
            arch = "x86_64",
        ),
    }

    is_freethreaded_yes = str(Label("//python/config_settings:_is_py_freethreaded_yes"))
    is_freethreaded_no = str(Label("//python/config_settings:_is_py_freethreaded_no"))
    return {
        p + suffix: platform_info(
            compatible_with = v.compatible_with,
            target_settings = [
                freethreadedness,
            ] + v.target_settings,
            os_name = v.os_name,
            arch = v.arch,
        )
        for p, v in platforms.items()
        for suffix, freethreadedness in {
            "": is_freethreaded_no,
            FREETHREADED: is_freethreaded_yes,
        }.items()
    }

PLATFORMS = _generate_platforms()

def get_release_info(platform, python_version, base_url = DEFAULT_RELEASE_BASE_URL, tool_versions = TOOL_VERSIONS):
    """Resolve the release URL for the requested interpreter version

    Args:
        platform: The platform string for the interpreter
        python_version: The version of the interpreter to get
        base_url: The URL to prepend to the 'url' attr in the tool_versions dict
        tool_versions: A dict listing the interpreter versions, their SHAs and URL

    Returns:
        A tuple of (filename, url, archive strip prefix, patches, patch_strip)
    """

    url = tool_versions[python_version]["url"]

    if type(url) == type({}):
        url = url[platform]

    if type(url) != type([]):
        url = [url]

    strip_prefix = tool_versions[python_version].get("strip_prefix", None)
    if type(strip_prefix) == type({}):
        strip_prefix = strip_prefix[platform]

    release_filename = None
    rendered_urls = []
    for u in url:
        p, _, _ = platform.partition(FREETHREADED)

        if FREETHREADED.lstrip("-") in platform:
            build = "{}+{}-full".format(
                FREETHREADED.lstrip("-"),
                {
                    "aarch64-apple-darwin": "pgo+lto",
                    "aarch64-unknown-linux-gnu": "lto",
                    "ppc64le-unknown-linux-gnu": "lto",
                    "riscv64-unknown-linux-gnu": "lto",
                    "s390x-unknown-linux-gnu": "lto",
                    "x86_64-apple-darwin": "pgo+lto",
                    "x86_64-pc-windows-msvc": "pgo",
                    "x86_64-unknown-linux-gnu": "pgo+lto",
                }[p],
            )
        else:
            build = INSTALL_ONLY

        if WINDOWS_NAME in platform and int(u.split("/")[0]) < 20250317:
            build = "shared-" + build

        release_filename = u.format(
            platform = p,
            python_version = python_version,
            build = build,
            ext = "tar.zst" if build.endswith("full") else "tar.gz",
        )
        if "://" in release_filename:  # is absolute url?
            rendered_urls.append(release_filename)
        else:
            rendered_urls.append("/".join([base_url, release_filename]))

    if release_filename == None:
        fail("release_filename should be set by now; were any download URLs given?")

    patches = tool_versions[python_version].get("patches", [])
    if type(patches) == type({}):
        if platform in patches.keys():
            patches = patches[platform]
        else:
            patches = []
    patch_strip = tool_versions[python_version].get("patch_strip", None)
    if type(patch_strip) == type({}):
        if platform in patch_strip.keys():
            patch_strip = patch_strip[platform]
        else:
            patch_strip = None

    return (release_filename, rendered_urls, strip_prefix, patches, patch_strip)

def gen_python_config_settings(name = ""):
    for platform in PLATFORMS.keys():
        native.config_setting(
            name = "{name}{platform}".format(name = name, platform = platform),
            flag_values = PLATFORMS[platform].flag_values,
            constraint_values = PLATFORMS[platform].compatible_with,
        )

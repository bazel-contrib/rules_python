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
load("//python/private:text_util.bzl", "render")

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
        "url": "20250612/cpython-{python_version}+20250612-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "75c2bcc055088e9d20109910c82960bfe4ec5c1ea481e2176002aad4d7049eab",
            "aarch64-unknown-linux-gnu": "1925b9aa73cd11633daa01756e32f9c319340c25e5338b151477691e8d99494b",
            "ppc64le-unknown-linux-gnu": "bf0ebbf8842aff64955ec2d9c8bdc4fef266ffd2a92cff13d2c761e7a0039331",
            "riscv64-unknown-linux-gnu": "a1623c1a3f4a91e4e022c08a8efb2177195bcdfcf715e1eb1612930324c68e3f",
            "s390x-unknown-linux-gnu": "39806ac64f2375e1b6e4b0f378d01add441f1d81953629f828224a9b874a640a",
            "x86_64-apple-darwin": "6565c263f28ae466f1b81cb902ac002bfcad7b1b04863e3576baa6c968dbf83a",
            "x86_64-pc-windows-msvc": "42a80636326ca998fadb8840de4cb50716f6df63f815a8e71a4c922d3d6c00d0",
            "x86_64-unknown-linux-gnu": "110ddaca41601b431041db6b4778584f671ca109ca25ef19fe32796026678358",
            "x86_64-unknown-linux-musl": "c3bdcc5ce8ee357d856b22f6aa72da3126dd400ac9a643e5df91625376efc23a",
        },
        "strip_prefix": "python",
    },
    "3.10.18": {
        "url": "20250612/cpython-{python_version}+20250612-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "ff6c9dd7172f82064f8d39fd4cd5d6bec77895ccffe480d846ff4a9750d14093",
            "aarch64-unknown-linux-gnu": "11cc65da5cb3a469bc67b6f91bac5ec00d2070394f462ef8867a4db8d0fc6903",
            "ppc64le-unknown-linux-gnu": "9fa6a75eb527016b0731faf2c9238dc4958ba85c41806f4c89efa6e12608cf86",
            "riscv64-unknown-linux-gnu": "723a026f2184b4785a55da22b52ed0c0612f938c28ac6400b314b61e1daf10de",
            "s390x-unknown-linux-gnu": "c43782f3efe25e0a0c62376643bd1bcdbde05c988aa86cc497df8031d619364a",
            "x86_64-apple-darwin": "92ecfbfb89e8137cc88cabc2f408d00758d67454d07c1691706d3dcccc8fc446",
            "x86_64-pc-windows-msvc": "d26dba4ec86f49ecbc6800e55f72691b9873115fa7c00f254f28dc04a03e8c13",
            "x86_64-unknown-linux-gnu": "c28f5698033f3ba47f0c0f054fcf6b9134ff5082b478663c7c7c25bb7e0c4422",
            "x86_64-unknown-linux-musl": "1b5c269a5eb04681e475aec673b1783e5f939f37dce305cd2e96eb0df186e9a2",
        },
        "strip_prefix": "python",
    },
    "3.11.13": {
        "url": "20250612/cpython-{python_version}+20250612-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "e272f0baca8f5a3cef29cc9c7418b80d0316553062ad3235205a33992155043c",
            "aarch64-unknown-linux-gnu": "c6959d0c17fc221a9acc56e4827f3fe7386b610402055950e4b767b3b6871a40",
            "ppc64le-unknown-linux-gnu": "22ab07e9bd167e2a7852a7b11b31cd91d090f3658e2ffc5bc6428751942cb1b9",
            "riscv64-unknown-linux-gnu": "4ca57a3e139cf47803909a88f4f3940d9ecfde42d8089a11f42074859bc9a122",
            "s390x-unknown-linux-gnu": "23cbd87fe9549ddda635ba9fb36b3622b5c939a10a39b25cd8c2587bb65e62ef",
            "x86_64-apple-darwin": "e2a3e2434ba140615f01ed9328e063076c8282a38c11cab983bdcd5d1bd582da",
            "x86_64-pc-windows-msvc": "cc28397fa47d28b98e1dc880b98cb061b76c88116b1d6028e04443f7221b30da",
            "x86_64-unknown-linux-gnu": "4dd2c710a828c8cfff384e0549141016a563a5e153d2819a7225ccc05a1a17c7",
            "x86_64-unknown-linux-musl": "130c6b55b06c92b7f952271fabedcdcfc06ac4717c133e0985ba27f799ed76b6",
        },
        "strip_prefix": "python",
    },
    "3.12.11": {
        "url": "20250612/cpython-{python_version}+20250612-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "c6d4843e8af496f034176908ae3384556680284653a4bff45eff07e43fe4ae34",
            "aarch64-unknown-linux-gnu": "19e8d91b8c5cdb41c485e0d7daa726db6dd64c9a459029f738d5e55ad8da7c6f",
            "ppc64le-unknown-linux-gnu": "32f489b4142ced7a3b476e25ac91ada4dc8aada1e771718a3aa9a0c818500a45",
            "riscv64-unknown-linux-gnu": "0c1a3e976a117bf40ce8d75ad4806166e503d554263a9051f7606dbeb01d91ee",
            "s390x-unknown-linux-gnu": "ee1a8451aaf49af330884553e2850961539b0563404c26241265ab0f0c929001",
            "x86_64-apple-darwin": "7e3468bde68650fb8f63b663a24c56d0bb3353abd16158939b1de0ad60dab195",
            "x86_64-pc-windows-msvc": "7b93afa91931dbc37b307a81b8680b30193736b5ef29a44ef6452f702c306e7a",
            "x86_64-unknown-linux-gnu": "8e8bb0dbc815fb0b3912e0d8fc0a4f4aaac002bfc1f6cb0fcd278f2888f11bcf",
            "x86_64-unknown-linux-musl": "b7464442265092259ee5f2e258c09cace4958f6b8733cff5e32bf8d2d6556a2a",
        },
        "strip_prefix": "python",
    },
    "3.13.5": {
        "url": "20250612/cpython-{python_version}+20250612-{platform}-{build}.{ext}",
        "sha256": {
            "aarch64-apple-darwin": "d7867270b8c7be69ec26a351afb6bf24802b1cd9818e8426bd69d439a619bf2d",
            "aarch64-unknown-linux-gnu": "685971ded0af96d1685941243ae1853c70c482b6f858dd86818760776d9c3cb9",
            "ppc64le-unknown-linux-gnu": "ee15fcf2b64034dba13127aa37992edacf2efe1b2bb3d62ffd45eb9bea7b2d83",
            "riscv64-unknown-linux-gnu": "c0f160ef9ab39c0f0e5baa00b1ecc3fff322c4ccbf1f04646c74559274ad5fc1",
            "s390x-unknown-linux-gnu": "49131a3d16c13aea76f9ef5ce57fc612a3062fc866f6fcf971e0de8f8a9b8a8f",
            "x86_64-apple-darwin": "d881b0226f1bef59b480c713126c54430a93ea21e5b39394c66927a412dd9907",
            "x86_64-pc-windows-msvc": "8f4d4c7d270406be1f8f93b9fd2fd13951e4da274ba59d170f411a20cb1725b3",
            "x86_64-unknown-linux-gnu": "f50dc28cfe99eccdadd4e74c2384607f7d5f50fc47447a39a4e24a793c07a9eb",
            "x86_64-unknown-linux-musl": "c4bc1cda684320455d41e56980adbacbda269c78527f3ee926711d5d0ff33834",
            "aarch64-apple-darwin-freethreaded": "a29cb4ef8adcd343e0f5bc5c4371cbc859fc7ce6d8f1a3c8d0cd7e44c4b9b866",
            "aarch64-unknown-linux-gnu-freethreaded": "0ef13d13e16b4e58f167694940c6db54591db50bbc7ba61be6901ed5a69ad27b",
            "ppc64le-unknown-linux-gnu-freethreaded": "66545ad4b09385750529ef09a665fc0b0ce698f984df106d7b167e3f7d59eace",
            "riscv64-unknown-linux-gnu-freethreaded": "a82a741abefa7db61b2aeef36426bd56da5c69dc9dac105d68fba7fe658943ca",
            "s390x-unknown-linux-gnu-freethreaded": "403c5758428013d5aa472841294c7b6ec91a572bb7123d02b7f1de24af4b0e13",
            "x86_64-apple-darwin-freethreaded": "52aeb1b4073fa3f180d74a0712ceabc86dd2b40be499599e2e170948fb22acde",
            "x86_64-pc-windows-msvc-freethreaded": "9da2f02d81597340163174ee91d91a8733dad2af53fc1b7c79ecc45a739a89d5",
            "x86_64-unknown-linux-gnu-freethreaded": "33fdd6c42258cdf0402297d9e06842b53d9413d70849cee61755b9b5fb619836",
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
    "3.14.0b2": {
        "url": "20250612/cpython-{python_version}+20250612-{platform}-{build}.{ext}",
        "sha256": {
            "aarch64-apple-darwin": "35c02e465af605eafd29d5931daadce724eeb8a3e7cc7156ac046991cb24f1c1",
            "aarch64-unknown-linux-gnu": "8c877a1b50eb2a9b34ddac5d52d50867f11ddc817f257eba4cbbc999a9edf2ea",
            "ppc64le-unknown-linux-gnu": "735bad9359eb36b55b76d9c6db122fe4357951d7850324c76e168055ca70e0a0",
            "riscv64-unknown-linux-gnu": "d4140196c052ba5832a439f84f6ca5b136bb16bceb8c5a52f5167a2c3f8b73b1",
            "s390x-unknown-linux-gnu": "2f440257e02d0a4fb4e93fcbb95b9066ec42bd56a2f03de05f55636e5afcb4b9",
            "x86_64-apple-darwin": "5144890b991e63fb73e2714c162c901c3b6f289ae0ef742df3673ab9824c844a",
            "x86_64-pc-windows-msvc": "903cfb0ae1766a572dcf62835ef24d3250a512974dcf785738ac0d6c06c9db5b",
            "x86_64-unknown-linux-gnu": "1c73b90a8febbd36fc973d7361a1be562e88437d95570721b701f03e59835600",
            "x86_64-unknown-linux-musl": "9cdd3983abfca2151661c25cb0fae50a30c8961e07d07ba643edab5be277ae09",
            "aarch64-apple-darwin-freethreaded": "1ae31adfed2a8425f08a945869d3bfd910e97acd150465de257d3ae3da37dc7c",
            "aarch64-unknown-linux-gnu-freethreaded": "f5fcf5e8310244ccd346aab2abdc2650ffb900a429cfb732c4884e238cba1782",
            "ppc64le-unknown-linux-gnu-freethreaded": "c1177510c359494b6a70601d9c810cdfc662f834c1d686abd487eb89d7a577ef",
            "riscv64-unknown-linux-gnu-freethreaded": "cb0f2d86b20f47c70a9c8647b01a35ab7d53cbcbde9ab89ffc8aacafb36cc2e4",
            "s390x-unknown-linux-gnu-freethreaded": "f38f126b31a55f37829ee581979214a6d2ac8a985ed7915b42c99d52af329d9f",
            "x86_64-apple-darwin-freethreaded": "4e022b8b7a1b2986aa5780fae34b5a89a1ac5ed11bea0c3349e674a6cb7e31c1",
            "x86_64-pc-windows-msvc-freethreaded": "35abc125304ec81a7be0d7ac54f515e7addd7dcba912882210d37720eaab1d7e",
            "x86_64-unknown-linux-gnu-freethreaded": "61383d43f639533a5105abad376bc497cc94dde8a1ed294f523d534c8cd99a8e",
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
    "3.14": "3.14.0b2",
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

def print_toolchains_checksums(name):
    """A macro to print checksums for a particular Python interpreter version.

    Args:
        name: {type}`str`: the name of the runnable target.
    """
    all_commands = []
    by_version = {}

    for python_version, metadata in TOOL_VERSIONS.items():
        by_version[python_version] = _commands_for_version(
            python_version = python_version,
            metadata = metadata,
        )
        all_commands.append(by_version[python_version])

    template = """\
cat > "$@" <<'EOF'
#!/bin/bash

set -o errexit -o nounset -o pipefail

echo "Fetching hashes..."

{commands}
EOF
    """

    native.genrule(
        name = name,
        srcs = [],
        outs = ["print_toolchains_checksums.sh"],
        cmd = select({
            "//python/config_settings:is_python_{}".format(version): template.format(
                commands = commands,
            )
            for version, commands in by_version.items()
        } | {
            "//conditions:default": template.format(commands = "\n".join(all_commands)),
        }),
        executable = True,
    )

def _commands_for_version(*, python_version, metadata):
    lines = []
    lines += [
        "cat <<EOB", # end of block
        "    \"{python_version}\": {{".format(python_version=python_version),
        "        \"url\": \"{url}\",".format(url=metadata["url"]),
        "        \"sha256\": {",
    ]

    for platform in metadata["sha256"].keys():
        for release_url in get_release_info(platform, python_version)[1]:
            # Do lines one by one so that the progress is seen better and use cat for ease of quotation
            lines += [
                "EOB",
                "cat <<EOB",
                "            \"{platform}\": \"$$({get_sha256})\",".format(
                    platform = platform,
                    get_sha256 = "curl --location --fail {release_url_sha256} 2>/dev/null || curl --location --fail {release_url} 2>/dev/null | shasum -a 256 | awk '{{ print $$1 }}'".format(
                        release_url = release_url,
                        release_url_sha256 = release_url + ".sha256",
                    ),
                )
            ]

    prefix = metadata["strip_prefix"]
    prefix = render.indent(
        render.dict(prefix) if type(prefix) == type({}) else repr(prefix),
        indent=" " * 8,
    ).lstrip()

    lines += [
        "        },",
        "        \"strip_prefix\": {strip_prefix},".format(strip_prefix = prefix),
        "    },",
        "EOB",
    ]

    return "\n".join(lines)

def gen_python_config_settings(name = ""):
    for platform in PLATFORMS.keys():
        native.config_setting(
            name = "{name}{platform}".format(name = name, platform = platform),
            flag_values = PLATFORMS[platform].flag_values,
            constraint_values = PLATFORMS[platform].compatible_with,
        )

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

load("//python/private:pbs_manifest.bzl", "parse_runtime_manifest")
load("//python/private:platform_info.bzl", "platform_info")

##load("@rules_python_internal//:manifest_tool_versions.bzl", "MANIFEST_ENTRIES")
load("//python/private:runtimes_manifest_workspace.bzl", "MANIFEST_TEXT")

# Values present in the @platforms//os package
MACOS_NAME = "osx"
LINUX_NAME = "linux"
WINDOWS_NAME = "windows"

FREETHREADED = "-freethreaded"
MUSL = "-musl"
INSTALL_ONLY = "install_only"

_GITHUB_PREFIX = "https://github.com/astral-sh/python-build-standalone/releases/download"
_LEGACY_GITHUB_PREFIX = "https://github.com/indygreg/python-build-standalone/releases/download"
_ASTRAL_PREFIX = "https://releases.astral.sh/github/python-build-standalone/releases/download"

DEFAULT_RELEASE_BASE_URL = _GITHUB_PREFIX
DEFAULT_RELEASE_BASE_URLS = [
    _GITHUB_PREFIX,
    _ASTRAL_PREFIX,
    _LEGACY_GITHUB_PREFIX,
]

# buildifier: disable=unsorted-dict-items
MINOR_MAPPING = {
    "3.9": "3.9.25",
    "3.10": "3.10.20",
    "3.11": "3.11.15",
    "3.12": "3.12.13",
    "3.13": "3.13.13",
    "3.14": "3.14.4",
    "3.15": "3.15.0a8",
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
        "aarch64-pc-windows-msvc": platform_info(
            compatible_with = [
                "@platforms//os:windows",
                "@platforms//cpu:aarch64",
            ],
            os_name = WINDOWS_NAME,
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
        "arm64e-apple-darwin": platform_info(
            compatible_with = [
                "@platforms//os:macos",
                "@platforms//cpu:arm64e",
            ],
            os_name = MACOS_NAME,
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

def get_release_info(platform, python_version, base_urls = DEFAULT_RELEASE_BASE_URLS, tool_versions = None):
    """Resolve the release URL for the requested interpreter version

    Args:
        platform: The platform string for the interpreter
        python_version: The version of the interpreter to get
        base_urls: The list of URLs to prepend to the 'url' attr in the tool_versions dict
        tool_versions: A dict listing the interpreter versions, their SHAs and URL

    Returns:
        A tuple of (filename, url, archive strip prefix, patches, patch_strip)
    """
    if tool_versions == None:
        tool_versions = TOOL_VERSIONS

    if type(base_urls) == type(""):
        base_urls = [base_urls]
    elif base_urls == None:
        base_urls = DEFAULT_RELEASE_BASE_URLS

    expanded_base_urls = []
    for b_url in base_urls:
        if b_url not in expanded_base_urls:
            expanded_base_urls.append(b_url)
        if b_url.startswith(_GITHUB_PREFIX):
            suffix = b_url[len(_GITHUB_PREFIX):]
            a_url = _ASTRAL_PREFIX + suffix
            if a_url not in expanded_base_urls:
                expanded_base_urls.append(a_url)
        elif b_url.startswith(_LEGACY_GITHUB_PREFIX):
            suffix = b_url[len(_LEGACY_GITHUB_PREFIX):]
            a_url = _ASTRAL_PREFIX + suffix
            if a_url not in expanded_base_urls:
                expanded_base_urls.append(a_url)
    base_urls = expanded_base_urls

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

        # Assume an unknown release_id is a newer url format
        release_id = 99999999
        url_parts = u.split("/")
        if len(url_parts) >= 2 and url_parts[-2].isdigit():
            maybe_release_id = url_parts[-2]
            release_id = int(maybe_release_id)

        if FREETHREADED.lstrip("-") in platform and release_id < 20260325:
            build = "{}+{}-full".format(
                FREETHREADED.lstrip("-"),
                {
                    "aarch64-apple-darwin": "pgo+lto",
                    "aarch64-pc-windows-msvc": "pgo",
                    "aarch64-unknown-linux-gnu": "lto" if release_id < 20250702 else "pgo+lto",
                    "ppc64le-unknown-linux-gnu": "lto",
                    "riscv64-unknown-linux-gnu": "lto",
                    "s390x-unknown-linux-gnu": "lto",
                    "x86_64-apple-darwin": "pgo+lto",
                    "x86_64-pc-windows-msvc": "pgo",
                    "x86_64-unknown-linux-gnu": "pgo+lto",
                    "x86_64-unknown-linux-musl": "pgo+lto",
                }[p],
            )
        else:
            build = INSTALL_ONLY

        if WINDOWS_NAME in platform and release_id < 20250317:
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
            for b_url in base_urls:
                rendered_urls.append("/".join([b_url, release_filename]))

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

def _manifest_entry_sort_key(entry):
    flavor_rank = {"full": 3, "install_only": 1, "install_only_stripped": 2}.get(entry.archive_flavor, 4)
    microarch = entry.microarch
    if not microarch:
        microarch_rank = 0
    elif microarch.startswith("v") and microarch[1:].isdigit():
        microarch_rank = int(microarch[1:])
    else:
        microarch_rank = 999
    return (flavor_rank, microarch_rank)

def _tool_versions_from_manifest_entries(entries, base_url = DEFAULT_RELEASE_BASE_URL):
    """Converts parsed manifest entries into the TOOL_VERSIONS dictionary format.

    Args:
        entries: {type}`list[struct]` the parsed manifest entries.
        base_url: {type}`str` fallback base URL for standalone distributions.

    Returns:
        {type}`dict[str, dict]` the tool versions map.
    """
    available_versions = {}
    entries = sorted(
        entries,
        key = _manifest_entry_sort_key,
    )

    for entry in entries:
        location = entry.location
        sha256 = entry.sha256
        py_version = entry.python_version

        matched_platform = "{}-{}-{}".format(entry.arch, entry.vendor, entry.os)
        if entry.libc:
            matched_platform += "-" + entry.libc
        if entry.freethreaded:
            matched_platform += "-freethreaded"

        if matched_platform not in PLATFORMS:
            continue

        archive_flavor = entry.archive_flavor
        if archive_flavor not in ["install_only", "install_only_stripped", "full"]:
            continue

        v_dict = available_versions.setdefault(py_version, {})
        if matched_platform in v_dict.get("sha256", {}):
            continue

        if "://" in location:
            urls = [location]
        else:
            urls = ["{}/{}".format(base_url, location)]

        strip_prefix = "python/install" if archive_flavor == "full" else "python"

        v_dict.setdefault("sha256", {})[matched_platform] = sha256
        v_dict.setdefault("url", {})[matched_platform] = urls
        v_dict.setdefault("strip_prefix", {})[matched_platform] = strip_prefix

    return available_versions

TOOL_VERSIONS = _tool_versions_from_manifest_entries(parse_runtime_manifest(MANIFEST_TEXT))

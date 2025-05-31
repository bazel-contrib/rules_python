# Copyright 2023 The Bazel Authors. All rights reserved.
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

"""
A starlark implementation of the wheel platform tag parsing to get the target platform.
"""

load("//python/private:version.bzl", "version")
load(":parse_whl_name.bzl", "parse_whl_name")

# The order of the dictionaries is to keep definitions with their aliases next to each
# other
_CPU_ALIASES = {
    "x86_32": "x86_32",
    "i386": "x86_32",
    "i686": "x86_32",
    "x86": "x86_32",
    "x86_64": "x86_64",
    "amd64": "x86_64",
    "aarch64": "aarch64",
    "arm64": "aarch64",
    "ppc": "ppc",
    "ppc64": "ppc",
    "ppc64le": "ppc64le",
    "s390x": "s390x",
    "arm": "arm",
    "armv6l": "arm",
    "armv7l": "arm",
}  # buildifier: disable=unsorted-dict-items

_OS_PREFIXES = {
    "linux": "linux",
    "manylinux": "linux",
    "musllinux": "linux",
    "macos": "osx",
    "win": "windows",
}  # buildifier: disable=unsorted-dict-items

_PY310 = version.parse("3.10")
_PY313 = version.parse("3.13")

# factor this out
def _is_supported(p, parsed, min_py_version):
    if parsed.abi_tag in ["none", "abi3"]:
        if not version.is_ge(p.version, min_py_version):
            # unsupported on target plat
            return False
    elif parsed.abi_tag not in p.abis:
        # unsupported
        return False

    if parsed.platform_tag == "any":
        return True

    # TODO @aignas 2025-06-01: handle priority
    for match_plat in p.whl_platforms:
        head, _, tail = match_plat.partition("*")
        for whl_plat in parsed.platform_tag.split("."):
            if not tail and match_plat == whl_plat:
                return True
            elif tail and whl_plat.startswith(head) and whl_plat.endswith(tail):
                return True

    return False

def select_whls(*, whls, want_platforms = {}, include_whls = {}, logger = None):
    """Select a subset of wheels suitable for target platforms from a list.

    Args:
        whls: {type}`list[struct]` candidates which have a `filename` attribute containing
            the `whl` filename.
        want_platforms: {type}`dict[str, struct]` The platforms in "{abi}_{os}_{cpu}" or
            "{os}_{cpu}" format for the keys and the values are options for further fine
            tuning the selection.
        include_whls: TODO
        logger: A logger for printing diagnostic messages.

    Returns:
        A filtered list of items from the `whls` arg where `filename` matches
        the selected criteria. If no match is found, an empty list is returned.
    """
    if not whls:
        return []

    # TODO @aignas 2025-06-01: do this want_platforms conversion before parse_requirements
    _want_platforms = []
    for p in want_platforms:
        if not p.startswith("cp3"):
            logger.fail("expected all platforms to start with ABI, but got: {}".format(p))
            return []

        abi, _, os_cpu = p.partition("_")
        target_version = version.parse(abi.replace("cp3", "3."), strict = True)
        abi, _, _ = abi.partition(".")
        want_abis = {
            abi: None,
        }

        # TODO @aignas 2025-05-31: move this to be defined by the configure flag
        # TODO @aignas 2025-05-31: think about how the version is matched
        if version.is_lt(target_version, _PY310):
            # The `m` wheels are only present for old Python versions
            want_abis["{}m".format(abi)] = None
        elif version.is_lt(target_version, _PY313):
            pass
        else:
            # Free threaded is present recently
            want_abis["{}t".format(abi)] = None

        include = include_whls.get(os_cpu)
        _want_platforms.append(struct(
            name = p,
            os_cpu = os_cpu,
            abis = want_abis,
            version = target_version,
            whl_platforms = include.platforms,
        ))

    compatible = {}
    for whl in whls:
        parsed = parse_whl_name(whl.filename)
        python_tag = parsed.python_tag
        _, _, python_tag = python_tag.rpartition(".")
        min_py_version = version.parse(python_tag[2:], strict = True)
        implementation = python_tag[:2]

        # if not ("cp" in supported_implementations or "py" in supported_implementations):
        #     if logger:
        #         logger.trace(lambda: "Discarding the whl because the whl does not support CPython, whl supported implementations are: {}".format(supported_implementations))
        #     continue

        for p in _want_platforms:
            if not _is_supported(p, parsed, min_py_version):
                continue

            compatible.setdefault(whl.filename, struct(
                whl = whl,
                implementation = implementation,
                version = version.key(min_py_version),
                parsed = parsed,
                target_platforms = [],
            )).target_platforms.append(p.name)

    # return unique whls
    candidates = {}
    for whl in compatible.values():
        for p in whl.target_platforms:
            candidates.setdefault(p, {}).setdefault(
                (
                    # prefer cp implementation
                    whl.implementation == "cp",
                    # prefer higher versions
                    whl.version,
                    # prefer abi3 over none
                    whl.parsed.abi_tag != "none",
                    # prefer cpx abi over abi3
                    whl.parsed.abi_tag != "abi3",
                    # prefer platform wheels
                    whl.parsed.platform_tag != "any",
                ),
                [],
            ).append(whl.whl.filename)

    ret = {
        candidates[key][sorted(v)[-1]][-1]: None
        for key, v in candidates.items()
    }
    return [whl for whl in whls if whl.filename in ret]

def whl_target_platforms(platform_tag, abi_tag = ""):
    """Parse the wheel abi and platform tags and return (os, cpu) tuples.

    Args:
        platform_tag (str): The platform_tag part of the wheel name. See
            ./parse_whl_name.bzl for more details.
        abi_tag (str): The abi tag that should be used for parsing.

    Returns:
        A list of structs, with attributes:
        * os: str, one of the _OS_PREFIXES values
        * cpu: str, one of the _CPU_PREFIXES values
        * abi: str, the ABI that the interpreter should have if it is passed.
        * target_platform: str, the target_platform that can be given to the
          wheel_installer for parsing whl METADATA.
    """
    cpus = _cpu_from_tag(platform_tag)

    abi = None
    if abi_tag not in ["", "none", "abi3"]:
        abi = abi_tag

    # TODO @aignas 2024-05-29: this code is present in many places, I think
    _, _, tail = platform_tag.partition("_")
    maybe_arch = tail
    major, _, tail = tail.partition("_")
    minor, _, tail = tail.partition("_")
    if not tail or not major.isdigit() or not minor.isdigit():
        tail = maybe_arch
        major = 0
        minor = 0

    for prefix, os in _OS_PREFIXES.items():
        if platform_tag.startswith(prefix):
            return [
                struct(
                    os = os,
                    cpu = cpu,
                    abi = abi,
                    version = (int(major), int(minor)),
                    target_platform = "_".join([abi, os, cpu] if abi else [os, cpu]),
                )
                for cpu in cpus
            ]

    print("WARNING: ignoring unknown platform_tag os: {}".format(platform_tag))  # buildifier: disable=print
    return []

def _cpu_from_tag(tag):
    candidate = [
        cpu
        for input, cpu in _CPU_ALIASES.items()
        if tag.endswith(input)
    ]
    if candidate:
        return candidate

    if tag == "win32":
        return ["x86_32"]
    elif tag == "win_ia64":
        return []
    elif tag.startswith("macosx"):
        if tag.endswith("universal2"):
            return ["x86_64", "aarch64"]
        elif tag.endswith("universal"):
            return ["x86_64", "aarch64"]
        elif tag.endswith("intel"):
            return ["x86_32"]

    return []

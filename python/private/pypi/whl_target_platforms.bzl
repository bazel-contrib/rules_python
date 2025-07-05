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

def _get_priority(*, tag, values):
    for priority, wp in enumerate(values):
        # TODO @aignas 2025-06-16: move the matcher validation out of this
        # TODO @aignas 2025-06-21: test the 'cp*' matching
        head, sep, tail = wp.partition("*")
        if "*" in tail:
            fail("only a single '*' can be present in the matcher")

        for p in tag.split("."):
            if not sep and p == head:
                return priority
            elif sep and p.startswith(head) and p.endswith(tail):
                return priority

    return None

def select_whl(*, whls, python_version, platforms, want_abis, implementation = "cp", limit = 1, logger = None):
    """Select a whl that is the most suitable for the given platform.

    Args:
        whls: {type}`list[struct]` a list of candidates which have a `filename`
            attribute containing the `whl` filename.
        python_version: {type}`str` the target python version.
        platforms: {type}`list[str]` the target platform identifiers that may contain
            a single `*` character.
        implementation: {type}`str` TODO
        want_abis: {type}`str` TODO
        limit: {type}`int` number of wheels to return. Defaults to 1.
        logger: {type}`struct` the logger instance.

    Returns:
        {type}`list[struct] | struct | None`, a single struct from the `whls` input
            argument or `None` if a match is not found. If the `limit` is greater than
            one, then we will return a list.
    """
    py_version = version.parse(python_version, strict = True)

    # Get the minor version instead
    # TODO @aignas 2025-06-27: do this more efficiently
    py_version = version.parse("{0}.{1}".format(*py_version.release), strict = True)
    candidates = {}

    for whl in whls:
        parsed = parse_whl_name(whl.filename)
        suffix = ""
        if parsed.abi_tag.startswith(implementation):
            v = parsed.abi_tag[2:]

            min_whl_py_version = version.parse(
                "{}.{}".format(v[0], v[1:].strip("tm")),
                strict = False,
            )
            if parsed.abi_tag.endswith("t"):
                suffix = "t"

            if not version.is_eq(py_version, min_whl_py_version):
                if logger:
                    logger.debug(lambda: "Discarding the wheel ('{}') because the min version supported based on the wheel ABI tag '{}' ({}) is not compatible with the provided target Python version '{}'".format(
                        whl.filename,
                        parsed.abi_tag,
                        min_whl_py_version.string,
                        py_version.string,
                    ))
                continue
        else:
            if parsed.python_tag.startswith("py"):
                pass
            elif not parsed.python_tag.startswith(implementation):
                if logger:
                    logger.debug(lambda: "Discarding the wheel because the implementation '{}' is not compatible with target implementation '{}'".format(
                        parsed.python_tag,
                        implementation,
                    ))
                continue

            if parsed.python_tag == "py2.py3":
                min_version = "2"
            else:
                min_version = parsed.python_tag[2:]

            if len(min_version) > 1:
                min_version = "{}.{}".format(min_version[0], min_version[1:])

            min_whl_py_version = version.parse(min_version, strict = True)
            if not version.is_ge(py_version, min_whl_py_version):
                if logger:
                    logger.debug(lambda: "Discarding the wheel because the min version supported based on the wheel ABI tag '{}' ({}) is not compatible with the provided target Python version '{}'".format(
                        parsed.abi_tag,
                        min_whl_py_version.string,
                        py_version.string,
                    ))
                continue

        abi_priority = _get_priority(
            tag = parsed.abi_tag,
            values = want_abis,
        )
        if abi_priority == None:
            if logger:
                logger.debug(lambda: "The abi '{}' does not match given list: {}".format(
                    parsed.abi_tag,
                    want_abis,
                ))
            continue
        platform_priority = _get_priority(
            tag = parsed.platform_tag,
            values = platforms,
        )
        if platform_priority == None:
            if logger:
                logger.debug(lambda: "The platform_tag '{}' does not match given list: {}".format(
                    parsed.platform_tag,
                    platforms,
                ))
            continue

        key = (
            # Ensure that we chose the highest compatible version
            parsed.python_tag.startswith(implementation),
            platform_priority,
            # prefer abi_tags in this order
            version.key(min_whl_py_version),
            abi_priority,
            suffix,
        )
        candidates.setdefault(key, whl)

    if not candidates:
        return None

    sorted_candidates = [i[1] for i in sorted(candidates.items())]
    if logger:
        logger.debug(lambda: "Sorted candidates:\n{}".format(
            "\n".join([c.filename for c in sorted_candidates]),
        ))
    results = sorted_candidates[-limit:] if sorted_candidates else None

    return results[-1] if limit == 1 else results

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

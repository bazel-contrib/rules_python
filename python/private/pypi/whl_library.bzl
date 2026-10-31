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

""

load(":patch_whl.bzl", "get_whl_patches", "patched_whl_name")
load(":pip_archive.bzl", "pip_archive", "pip_archive_attrs")
load(":whl_archive.bzl", "whl_archive", "whl_archive_attrs")
load(":whl_file_repo.bzl", "whl_file_repo", "whl_file_repo_attrs")

def _filter(kwargs, subset, debug = False):
    dropped = {}
    filtered = {}
    for k, v in kwargs.items():
        if k in subset:
            filtered[k] = v
        else:
            dropped[k] = v

    if debug:
        print("Ignored args: {}".format(dropped))  # buildifier: disable=print

    return filtered

def whl_library(name, repo = None, **kwargs):
    """Create a whl_library.

    This proxies to one of the underlying implementations:
    * {obj}`whl_archive`
    * {obj}`pip_archive`

    URL wheels are downloaded temporarily for extraction, then removed.
    A sibling `<name>_whl` repository supplies the original archive lazily,
    when a wheel target is requested. Extraction does not depend on it.
    Matching patches are applied in the wheel-file repository instead;
    extraction and wheel targets then consume the same patched archive.

    Args:
        name: {type}`str` The name of the repo.
        repo: Unused, will be dropped in the next major release.
        **kwargs: The args passed to the underlying implementation.

    Returns:
        the repo metadata.
    """
    _ = repo  # buildifier: disable=unused-variable

    whl_file = kwargs.get("whl_file")
    urls = kwargs.get("urls", [])
    filename = kwargs.get("filename")

    # compatibility shim for cases for repo_prefix is still used by the called
    kwargs.setdefault("dep_template", "@{}{{name}}//:{{target}}".format(kwargs.pop("repo_prefix", "")))

    if whl_file or (urls and filename and filename.endswith(".whl")):
        wheel_filename = filename or str(whl_file).split(":")[-1].split("/")[-1]
        patches = get_whl_patches(kwargs.get("whl_patches", {}), wheel_filename)
        if patches:
            # Caller-owned wheels are often already supplied by <name>_whl.
            # Give their patched output a distinct repository name.
            file_repo = name + ("_patched_whl" if whl_file else "_whl")
            whl_file_repo(
                name = file_repo,
                patches = {patch: str(strip) for patch, strip in patches.items()},
                **_filter(kwargs, whl_file_repo_attrs)
            )
            kwargs["whl_file"] = "@{}//:{}".format(file_repo, patched_whl_name(wheel_filename))
            kwargs["whl_patches"] = {}
        elif not whl_file:
            whl_file_repo(name = name + "_whl", **_filter(kwargs, whl_file_repo_attrs))
            kwargs["downloaded_whl"] = "@{}//:{}".format(name + "_whl", filename)
        whl_archive(name = name, **_filter(kwargs, whl_archive_attrs))
    else:
        pip_archive(name = name, **_filter(kwargs, pip_archive_attrs))

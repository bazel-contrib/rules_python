# Copyright 2023 The Bazel Authors. All rights reserved.
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

"""A small utility to patch a file in the repository context natively.

This replaces the previous approach that depended on running Python to
repack patched wheels. Instead, after extracting and patching, we fix
the RECORD file natively in Starlark and repack using system zip.
"""

load("@rules_python_internal//:rules_python_config.bzl", rp_config = "config")
load("//python/private:repo_utils.bzl", "repo_utils")
load(":parse_whl_name.bzl", "parse_whl_name")

_DUMMY_SHA256 = "sha256=0"

_RECORD_EXCLUDES = {
    "INSTALLER": None,
    "RECORD": None,
    "RECORD.jws": None,
    "RECORD.p7s": None,
    "REQUESTED": None,
}

def patched_whl_name(original_whl_name):
    """Return the new filename to output the patched wheel.

    Args:
        original_whl_name: {type}`str` the whl name of the original file.

    Returns:
        {type}`str` an output name to write the patched wheel to.
    """
    parsed_whl = parse_whl_name(original_whl_name)
    version = parsed_whl.version
    suffix = "patched"
    if "+" in version:
        version = "{}.{}".format(version, suffix)
    else:
        version = "{}+{}".format(version, suffix)

    return "{distribution}-{version}-{python_tag}-{abi_tag}-{platform_tag}.whl".format(
        distribution = parsed_whl.distribution,
        version = version,
        python_tag = parsed_whl.python_tag,
        abi_tag = parsed_whl.abi_tag,
        platform_tag = parsed_whl.platform_tag,
    )

def patch_whl(rctx, *, whl_path, patches):
    """Patch a whl file and repack it natively.

    The wheel is extracted, patched, missing RECORD entries are added
    with dummy sha256 and size values, and finally the wheel is
    repacked using system zip.

    Args:
        rctx: repository_ctx
        whl_path: The whl file name to be patched.
        patches: a label-keyed-int dict that has the patch files as keys and
            the patch_strip as the value.

    Returns:
        value of the repackaging action.
    """
    whl_input = rctx.path(whl_path)

    repo_utils.extract(
        rctx,
        archive = whl_input,
        supports_whl_extraction = rp_config.supports_whl_extraction,
        extract_needs_chmod = rp_config.extract_needs_chmod,
    )

    if not patches:
        fail("Trying to patch wheel without any patches")

    for patch_file, patch_strip in patches.items():
        rctx.patch(patch_file, strip = patch_strip)

    _fix_record(rctx)

    whl_patched = patched_whl_name(whl_input.basename)

    rctx.delete(whl_input)
    _repack_whl(rctx, output = whl_patched)

    return rctx.path(whl_patched)

def _fix_record(rctx):
    """Add missing file entries to RECORD with dummy sha256 and file size."""
    for entry in rctx.path(".").readdir():
        if not entry.basename.endswith(".dist-info"):
            continue

        record_path = entry.get_child("RECORD")
        if not record_path.exists:
            continue

        all_files = _collect_files(rctx)
        record_rel = repo_utils.repo_root_relative_path(rctx, record_path)

        new_content = fix_record_content(
            record_content = rctx.read(record_path),
            all_files = all_files,
            record_rel = record_rel,
        )
        if new_content != None:
            rctx.file(record_path, new_content)

def fix_record_content(record_content, all_files, record_rel):
    """Add missing file entries to RECORD content with dummy sha256 and size.

    Args:
        record_content: {type}`str` The existing RECORD file content.
        all_files: {type}`dict[str, bool]` All files in the directory, keys
            are repo-root-relative paths.
        record_rel: {type}`str` The repo-root-relative path to the RECORD file.

    Returns:
        {type}`str | None` The new RECORD content if entries were added,
        or None if no changes were needed.
    """
    has_trailing_newline = record_content.endswith("\n")
    lines = record_content.split("\n")

    is_all_quoted = True
    has_content = False
    existing = {}
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        has_content = True
        if not stripped.startswith('"'):
            is_all_quoted = False
        parts = stripped.split(",")
        if len(parts) >= 1:
            fname = parts[0].strip('"')
            existing[fname] = True

    if not has_content:
        is_all_quoted = False

    existing[record_rel] = True

    added = []
    for fpath in sorted(all_files.keys()):
        if fpath in existing:
            continue
        basename = fpath.split("/")[-1] if "/" in fpath else fpath
        if basename in _RECORD_EXCLUDES:
            continue
        if fpath.endswith(".whl"):
            continue
        added.append(fpath)

    if not added:
        return None

    new_lines = list(lines)
    if not has_trailing_newline:
        new_lines.append("")
    if is_all_quoted:
        for fpath in added:
            new_lines.append('"{file}",{sha256},0'.format(
                file = fpath,
                sha256 = _DUMMY_SHA256,
            ))
    else:
        for fpath in added:
            new_lines.append("{file},{sha256},0".format(
                file = fpath,
                sha256 = _DUMMY_SHA256,
            ))
    new_lines.append("")

    return "\n".join(new_lines)

def _collect_files(rctx):
    """Collect all file paths relative to the repo root (iterative)."""
    result = {}
    paths = [(rctx.path("."), "")]
    for _ in range(10000000):
        if not paths:
            break
        path, prefix = paths.pop()
        for entry in path.readdir():
            rel = prefix + "/" + entry.basename if prefix else entry.basename
            if entry.is_dir:
                paths.append((entry, rel))
            else:
                result[rel] = True
    return result

def _repack_whl(rctx, *, output):
    """Repack the current directory into a wheel file using system zip."""
    os_name = repo_utils.get_platforms_os_name(rctx)
    if os_name == "windows":
        _repack_whl_windows(rctx, output = output)
    else:
        _repack_whl_unix(rctx, output = output)

def _repack_whl_unix(rctx, *, output):
    repo_utils.execute_checked(
        rctx,
        op = "PatchWhl",
        arguments = [
            "zip",
            "-0",
            "-X",
            str(output),
            "-r",
            ".",
        ],
    )

def _repack_whl_windows(rctx, *, output):
    powershell_exe = rctx.which("powershell.exe") or rctx.which("powershell")
    if not powershell_exe:
        fail("powershell not found on PATH")

    script_path = rctx.path(Label("//python/private/pypi:repack_whl.ps1"))

    repo_utils.execute_checked(
        rctx,
        op = "PatchWhl",
        arguments = [
            powershell_exe,
            "-NoProfile",
            "-File",
            str(script_path),
            "-Output",
            str(output),
        ],
    )

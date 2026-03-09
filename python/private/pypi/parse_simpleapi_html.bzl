# Copyright 2024 The Bazel Authors. All rights reserved.
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
Parse SimpleAPI HTML in Starlark.
"""

load(":version_from_filename.bzl", "version_from_filename")

def parse_simpleapi_html(*, content):
    """Get the package URLs for given shas by parsing the Simple API HTML.

    Args:
        content(str): The Simple API HTML content.

    Returns:
        A list of structs with:
        * filename: The filename of the artifact.
        * version: The version of the artifact.
        * url: The URL to download the artifact.
        * sha256: The sha256 of the artifact.
        * metadata_sha256: The whl METADATA sha256 if we can download it. If this is
          present, then the 'metadata_url' is also present. Defaults to "".
        * metadata_url: The URL for the METADATA if we can download it. Defaults to "".
    """
    sdists = {}
    whls = {}
    lines = content.split("<a href=\"")

    _, _, api_version = lines[0].partition("name=\"pypi:repository-version\" content=\"")
    api_version, _, _ = api_version.partition("\"")

    # We must assume the 1.0 if it is not present
    # See https://packaging.python.org/en/latest/specifications/simple-repository-api/#clients
    api_version = api_version or "1.0"
    api_version = tuple([int(i) for i in api_version.split(".")])

    if api_version >= (2, 0):
        # We don't expect to have version 2.0 here, but have this check in place just in case.
        # https://packaging.python.org/en/latest/specifications/simple-repository-api/#versioning-pypi-s-simple-api
        fail("Unsupported API version: {}".format(api_version))

    # Each line follows the following pattern
    # <a href="https://...#sha256=..." attribute1="foo" ... attributeN="bar">filename</a><br />
    sha256s_by_version = {}
    for line in lines[1:]:
        dist_url, _, tail = line.partition("#sha256=")

        sha256, _, tail = tail.partition("\"")

        # See https://packaging.python.org/en/latest/specifications/simple-repository-api/#adding-yank-support-to-the-simple-api
        yanked = "data-yanked" in line

        head, _, _ = tail.rpartition("</a>")
        maybe_metadata, _, filename = head.rpartition(">")
        version = version_from_filename(filename)
        sha256s_by_version.setdefault(version, []).append(sha256)

        metadata_sha256 = ""
        metadata_url = ""
        for metadata_marker in ["data-core-metadata", "data-dist-info-metadata"]:
            metadata_marker = metadata_marker + "=\"sha256="
            if metadata_marker in maybe_metadata:
                # Implement https://peps.python.org/pep-0714/
                _, _, tail = maybe_metadata.partition(metadata_marker)
                metadata_sha256, _, _ = tail.partition("\"")
                metadata_url = dist_url + ".metadata"
                break

        if filename.endswith(".whl"):
            whls[sha256] = struct(
                filename = filename,
                version = version,
                url = dist_url,
                sha256 = sha256,
                metadata_sha256 = metadata_sha256,
                metadata_url = metadata_url,
                yanked = yanked,
            )
        else:
            sdists[sha256] = struct(
                filename = filename,
                version = version,
                url = dist_url,
                sha256 = sha256,
                metadata_sha256 = "",
                metadata_url = "",
                yanked = yanked,
            )

    return struct(
        sdists = sdists,
        whls = whls,
        sha256s_by_version = sha256s_by_version,
    )

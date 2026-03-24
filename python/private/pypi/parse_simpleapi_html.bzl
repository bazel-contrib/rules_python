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

load("//python/private:normalize_name.bzl", "normalize_name")
load(":version_from_filename.bzl", "version_from_filename")

def parse_simpleapi_html(*, content, parse_index = False):
    """Get the package URLs for given shas by parsing the Simple API HTML.

    Args:
        content: {type}`str` The Simple API HTML content.
        parse_index: {type}`bool` whether to parse the content as the index page of the PyPI index,
            e.g. the `https://pypi.org/simple/`. This only has the URLs for the individual package.

    Returns:
        If it is the index page, return the map of package to URL it can be queried from.
        Otherwise, a list of structs with:
          * filename: {type}`str` The filename of the artifact.
          * version: {type}`str` The version of the artifact.
          * url: {type}`str` The URL to download the artifact.
          * sha256: {type}`str` The sha256 of the artifact.
          * metadata_sha256: {type}`str` The whl METADATA sha256 if we can download it. If this is
            present, then the 'metadata_url' is also present. Defaults to "".
          * metadata_url: {type}`str` The URL for the METADATA if we can download it. Defaults to "".
          * yanked: {type}`str | None` the yank reason if the package is yanked. If it is not yanked,
              then it will be `None`. An empty string yank reason means that the package is yanked but
              the reason is not provided.
    """
    sdists = {}
    whls = {}
    sha256s_by_version = {}

    # 1. Faster Version Extraction
    # Search only the first 2KB for versioning metadata instead of splitting everything
    api_version = (1, 0)
    meta_idx = content.find('name="pypi:repository-version"')
    if meta_idx != -1:
        # Find 'content="' after the name attribute
        v_start = content.find('content="', meta_idx)
        if v_start != -1:
            v_end = content.find('"', v_start + 9)
            v_str = content[v_start + 9:v_end]
            if v_str:
                api_version = tuple([int(i) for i in v_str.split(".")])

    if api_version >= (2, 0):
        # We don't expect to have version 2.0 here, but have this check in place just in case.
        # https://packaging.python.org/en/latest/specifications/simple-repository-api/#versioning-pypi-s-simple-api
        fail("Unsupported API version: {}".format(api_version))

    packages = {}

    # 2. Iterate using find() to avoid huge list allocations from .split("<a ")
    cursor = 0
    for _ in range(1000000):  # Safety break for Starlark
        start_tag = content.find("<a ", cursor)
        if start_tag == -1:
            break

        # Find the closing </a> tag first, then find the end of the opening
        # <a ...> tag using rfind. This correctly handles attributes that
        # contain > characters, e.g. data-requires-python=">=3.6".
        end_tag = content.find("</a>", start_tag)
        if end_tag == -1:
            break
        tag_end = content.rfind(">", start_tag, end_tag)
        if tag_end == -1 or tag_end <= start_tag:
            cursor = end_tag + 4
            continue

        # Extract only the necessary slices
        filename = content[tag_end + 1:end_tag].strip()
        attr_part = content[start_tag + 3:tag_end]

        # Update cursor for next iteration
        cursor = end_tag + 4

        attrs = _parse_attrs(attr_part)
        href = attrs.get("href", "")
        if not href:
            continue

        if parse_index:
            pkg_name = filename
            packages[normalize_name(pkg_name)] = href
            continue

        # 3. Efficient Attribute Parsing
        dist_url, _, sha256 = href.partition("#sha256=")

        # Handle Yanked status
        yanked = None
        if "data-yanked" in attrs:
            yanked = _unescape_pypi_html(attrs["data-yanked"])

        version = version_from_filename(filename)
        sha256s_by_version.setdefault(version, []).append(sha256)

        # 4. Optimized Metadata Check (PEP 714)
        metadata_sha256 = ""
        metadata_url = ""

        # Dist-info is more common in modern PyPI
        m_val = attrs.get("data-dist-info-metadata") or attrs.get("data-core-metadata")
        if m_val and m_val != "false":
            _, _, metadata_sha256 = m_val.partition("sha256=")
            metadata_url = dist_url + ".metadata"

        # 5. Result object
        dist = struct(
            filename = filename,
            version = version,
            url = dist_url,
            sha256 = sha256,
            metadata_sha256 = metadata_sha256,
            metadata_url = metadata_url,
            yanked = yanked,
        )

        if filename.endswith(".whl"):
            whls[sha256] = dist
        else:
            sdists[sha256] = dist

    if parse_index:
        return packages

    return struct(
        sdists = sdists,
        whls = whls,
        sha256s_by_version = sha256s_by_version,
    )

def _parse_attrs(attr_string):
    """Parses attributes from a pre-sliced string."""
    attrs = {}
    parts = attr_string.split('"')

    for i in range(0, len(parts) - 1, 2):
        raw_key = parts[i].strip()
        if not raw_key:
            continue

        key_parts = raw_key.split(" ")
        current_key = key_parts[-1].rstrip("=")

        # Batch handle booleans
        for j in range(len(key_parts) - 1):
            b = key_parts[j].strip()
            if b:
                attrs[b] = ""

        attrs[current_key] = parts[i + 1]

    # Final trailing boolean check
    last = parts[-1].strip()
    if last:
        for b in last.split(" "):
            if b:
                attrs[b] = ""
    return attrs

def _unescape_pypi_html(text):
    """Unescape HTML text.

    Decodes standard HTML entities used in the Simple API.
    Specifically targets characters used in URLs and attribute values.

    Args:
        text: {type}`str` The text to replace.

    Returns:
        A string with unescaped characters
    """

    # 1. Short circuit for the most common case
    if not text or "&" not in text:
        return text

    # 2. Check for the most frequent PEP 503 entities first (version constraints).
    # Re-ordering based on frequency reduces unnecessary checks for rare entities.
    if "&gt;" in text:
        text = text.replace("&gt;", ">")
    if "&lt;" in text:
        text = text.replace("&lt;", "<")

    # 3. Grouped check for numeric entities.
    # If '&#' isn't there, we skip 4 distinct string scans.
    if "&#" in text:
        if "&#39;" in text:
            text = text.replace("&#39;", "'")
        if "&#x27;" in text:
            text = text.replace("&#x27;", "'")
        if "&#10;" in text:
            text = text.replace("&#10;", "\n")
        if "&#13;" in text:
            text = text.replace("&#13;", "\r")

    if "&quot;" in text:
        text = text.replace("&quot;", '"')

    # 4. Handle ampersands last to prevent double-decoding.
    if "&amp;" in text:
        text = text.replace("&amp;", "&")

    return text

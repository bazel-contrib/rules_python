# Copyright 2026 The Bazel Authors. All rights reserved.
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

"""Helpers for working with distribution hash digests.

Both the requirement `--hash=<algo>:<digest>` option (PEP 508 tooling) and the
Simple API `#<algo>=<digest>` URL fragments (PEP 503) or `hashes` dicts
(PEP 691) may use any algorithm from `hashlib.algorithms_guaranteed`, even
though `sha256` is the most common one.
"""

# The names from `hashlib.algorithms_guaranteed`, which PEP 691 uses as the
# set of valid hash names and PEP 503 strongly recommends fragments to come
# from.
HASH_ALGOS = [
    "blake2b",
    "blake2s",
    "md5",
    "sha1",
    "sha224",
    "sha256",
    "sha384",
    "sha3_224",
    "sha3_256",
    "sha3_384",
    "sha3_512",
    "sha512",
    "shake_128",
    "shake_256",
]

# The algorithms supported by the Subresource Integrity format understood by
# `ctx.download(integrity = ...)`, strongest first.
_SRI_ALGOS = ["sha512", "sha384", "sha256"]

_HEX = "0123456789abcdef"
_B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

def _hex_to_b64(hex_digest):
    if len(hex_digest) % 2:
        return None

    data = []
    for i in range(0, len(hex_digest), 2):
        hi = _HEX.find(hex_digest[i])
        lo = _HEX.find(hex_digest[i + 1])
        if hi < 0 or lo < 0:
            return None
        data.append(hi * 16 + lo)

    out = []
    for i in range(0, len(data) // 3 * 3, 3):
        n = (data[i] << 16) | (data[i + 1] << 8) | data[i + 2]
        out.append(_B64[n >> 18])
        out.append(_B64[(n >> 12) & 63])
        out.append(_B64[(n >> 6) & 63])
        out.append(_B64[n & 63])

    rem = len(data) % 3
    if rem == 1:
        n = data[-1] << 16
        out.append(_B64[n >> 18])
        out.append(_B64[(n >> 12) & 63])
        out.append("==")
    elif rem == 2:
        n = (data[-2] << 16) | (data[-1] << 8)
        out.append(_B64[n >> 18])
        out.append(_B64[(n >> 12) & 63])
        out.append(_B64[(n >> 6) & 63])
        out.append("=")

    return "".join(out)

def hex_to_sri(algo, hex_digest):
    """Convert a hex digest to a Subresource Integrity value.

    Args:
        algo: {type}`str` the hash algorithm name, e.g. `sha512`.
        hex_digest: {type}`str` the hex encoded digest.

    Returns:
        {type}`str` the SRI value (e.g. `sha512-...`) that can be passed to
        `ctx.download(integrity = ...)` or an empty string if the algorithm
        cannot be expressed as SRI or the digest is not valid hex.
    """
    if algo not in _SRI_ALGOS or not hex_digest:
        return ""

    b64 = _hex_to_b64(hex_digest.lower())
    if b64 == None:
        return ""

    return "{}-{}".format(algo, b64)

def integrity_from_hashes(hashes):
    """Get the SRI value of the strongest supported digest.

    Args:
        hashes: {type}`dict[str, str]` mapping of hash algorithm name to the
            hex encoded digest.

    Returns:
        {type}`str` the SRI value or an empty string if none of the digests
        use an SRI supported algorithm.
    """
    for algo in _SRI_ALGOS:
        sri = hex_to_sri(algo, hashes.get(algo, ""))
        if sri:
            return sri

    return ""

def preferred_digest(hashes):
    """Get a hex digest that identifies an artifact, e.g. for repo naming.

    Args:
        hashes: {type}`dict[str, str]` mapping of hash algorithm name to the
            hex encoded digest.

    Returns:
        {type}`str` the digest of the most preferred algorithm present or an
        empty string if there are no digests.
    """
    if not hashes:
        return ""

    for algo in ["sha256", "sha512", "sha384"]:
        if hashes.get(algo):
            return hashes[algo]

    return hashes[sorted(hashes.keys())[0]]

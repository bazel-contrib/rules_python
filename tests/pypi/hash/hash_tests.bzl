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

""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private/pypi:hash.bzl", "hash")  # buildifier: disable=bzl-visibility

_tests = []

# The digests of b"rules_python" with the SRI values calculated with:
#   python3 -c 'import base64, hashlib; h = hashlib.sha512(b"rules_python").digest(); print(base64.b64encode(h))'
_SHA256 = "a90bb21ddf552d508565aa2f0d78ac13297e6c407e39eb578eeac09e62c5da3a"
_SHA256_SRI = "sha256-qQuyHd9VLVCFZaovDXisEyl+bEB+OetXjurAnmLF2jo="
_SHA384 = "7407ad30f83623cabf9139bd80edb332516880321ab2a20fa0f281767675bfc10b53555eb5042aa58de4b9345f5f70b6"
_SHA384_SRI = "sha384-dAetMPg2I8q/kTm9gO2zMlFogDIasqIPoPKBdnZ1v8ELU1VetQQqpY3kuTRfX3C2"
_SHA512 = "127af31fba52ce5ac96a4bc0f1b31c31c12367feace2b7dbb81066df479883add9dd6166495b126b76ac8c624d254b6a4ba3fbb628e8dcf0a34e1b0b065f619f"
_SHA512_SRI = "sha512-EnrzH7pSzlrJakvA8bMcMcEjZ/6s4rfbuBBm30eYg63Z3WFmSVsSa3asjGJNJUtqS6P7tijo3PCjThsLBl9hnw=="

def _test_digest(env):
    env.expect.that_str(hash.digest("sha256", _SHA256)).equals("sha256:" + _SHA256)

    # The algorithm name is normalized to lower case.
    env.expect.that_str(hash.digest("SHA256", _SHA256)).equals("sha256:" + _SHA256)

    # Unknown algorithms and empty digests yield nothing.
    env.expect.that_str(hash.digest("egg", "foo")).equals("")
    env.expect.that_str(hash.digest("sha256", "")).equals("")
    env.expect.that_str(hash.digest("", "")).equals("")

_tests.append(_test_digest)

def _test_hex_to_sri(env):
    env.expect.that_str(hash.hex_to_sri("sha256", _SHA256)).equals(_SHA256_SRI)
    env.expect.that_str(hash.hex_to_sri("sha384", _SHA384)).equals(_SHA384_SRI)
    env.expect.that_str(hash.hex_to_sri("sha512", _SHA512)).equals(_SHA512_SRI)

    # Upper case digests are accepted.
    env.expect.that_str(hash.hex_to_sri("sha512", _SHA512.upper())).equals(_SHA512_SRI)

    # Algorithms that SRI does not support yield nothing.
    env.expect.that_str(hash.hex_to_sri("md5", "0" * 32)).equals("")
    env.expect.that_str(hash.hex_to_sri("blake2b", "0" * 128)).equals("")

    # Invalid digests yield nothing.
    env.expect.that_str(hash.hex_to_sri("sha256", "")).equals("")
    env.expect.that_str(hash.hex_to_sri("sha256", "abc")).equals("")
    env.expect.that_str(hash.hex_to_sri("sha256", "not-hex!")).equals("")

_tests.append(_test_hex_to_sri)

def _test_integrity(env):
    env.expect.that_str(hash.integrity("")).equals("")
    env.expect.that_str(hash.integrity("md5:" + "0" * 32)).equals("")
    env.expect.that_str(hash.integrity("sha256:" + _SHA256)).equals(_SHA256_SRI)
    env.expect.that_str(hash.integrity("sha384:" + _SHA384)).equals(_SHA384_SRI)
    env.expect.that_str(hash.integrity("sha512:" + _SHA512)).equals(_SHA512_SRI)

_tests.append(_test_integrity)

def _test_preferred_digest(env):
    env.expect.that_str(hash.preferred_digest([])).equals("")
    env.expect.that_str(hash.preferred_digest([""])).equals("")

    # sha256 stays preferred so that the repo names remain stable.
    env.expect.that_str(hash.preferred_digest([
        "sha256:" + _SHA256,
        "sha512:" + _SHA512,
    ])).equals("sha256:" + _SHA256)

    # Otherwise the strongest SRI supported algorithm wins.
    env.expect.that_str(hash.preferred_digest([
        "sha384:" + _SHA384,
        "sha512:" + _SHA512,
    ])).equals("sha512:" + _SHA512)

    # And anything else is picked alphabetically for determinism.
    env.expect.that_str(hash.preferred_digest([
        "md5:deadb00f",
        "blake2b:deadbeef",
    ])).equals("blake2b:deadbeef")

_tests.append(_test_preferred_digest)

def hash_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)

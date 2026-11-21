# Copyright 2025 The Bazel Authors. All rights reserved.
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

"""This module is for parsing PEP508 requires-dist and requirements lines.
"""

load("@pypackaging.bzl", "pypackaging")

def requirement(spec):
    """Parse a PEP508 requirement line

    Args:
        spec: {type}`str` requirement line that will be parsed. The options
            of a `requirements.txt` line, e.g. `--hash`, are ignored.

    Returns:
        A struct with the information.
    """

    # The options are not a part of PEP 508.
    spec, _, _ = spec.partition(" --")

    head, semicolon, marker = spec.partition(";")
    name, at, url = head.partition("@")
    if at and "==" in name:
        # PEP 508 does not allow a version for the direct URL requirements,
        # but `name==version @ url` has always been accepted here, so that
        # the version of the distribution is known.
        name, _, _ = name.partition("==")
        spec = name + at + url + semicolon + marker

    req = pypackaging.requirements.parse(spec)

    return struct(
        name = req.name,
        name_ = req.name.replace("-", "_"),
        marker = req.marker_str or "",
        extras = [e.replace("-", "_") for e in req.extras],
    )

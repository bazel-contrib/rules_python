# Copyright 2024 The Bazel Authors. All rights reserved.
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

"""Creates the __main__.py for a zipapp by populating a template.

This program also calculates a hash of the application files to include in
the template, which allows making the extraction directory unique to the
content of the zipapp.
"""

import argparse
import hashlib
import os


def main():
    parser = argparse.ArgumentParser(fromfile_prefix_chars="@")
    parser.add_argument("--template", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--substitution", action="append", default=[])
    parser.add_argument("hash_inputs", nargs="*")
    args = parser.parse_args()

    # We want the hash to be deterministic.
    # The order of files matters for the hash.
    # We hash both the short path (to capture structure) and the content.
    # Wait, we only have the full path here.
    # Bazel provides full paths.
    
    h = hashlib.sha256()
    for path in sorted(args.hash_inputs):
        # We don't have the 'short_path' here easily unless we pass it.
        # But for the purpose of a unique hash, the full path is probably fine
        # as long as it's stable within a build.
        # However, full paths in Bazel can contain 'bazel-out/k8-fastbuild/bin/...'.
        # That's still stable for a given configuration.
        h.update(path.encode("utf-8"))
        if os.path.isfile(path):
            with open(path, "rb") as f:
                while True:
                    chunk = f.read(65536)
                    if not chunk:
                        break
                    h.update(chunk)

    app_hash = h.hexdigest()

    substitutions = {"%APP_HASH%": app_hash}
    for s in args.substitution:
        key, val = s.split("=", 1)
        substitutions[key] = val

    with open(args.template, "r", encoding="utf-8") as f:
        content = f.read()

    for key, val in substitutions.items():
        content = content.replace(key, val)

    with open(args.output, "w", encoding="utf-8") as f:
        f.write(content)


if __name__ == "__main__":
    main()

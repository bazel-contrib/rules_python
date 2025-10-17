#!/usr/bin/env bash
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

# This script finds Bazel sub-workspaces and marks them, and all their BUILD
# containing directories, as ignored by the root level bazel project, via the
# `--deleted_packages` flag.

set -euo pipefail
set -x

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$DIR/.."
BAZELRC="$ROOT_DIR/.bazelrc"

# Find all packages in sub-workspaces
found_packages() {
    cd "$ROOT_DIR"
    (
        find . -mindepth 2 \( -name WORKSPACE -o -name MODULE.bazel \) |
            while read -r marker; do
                workspace_dir="$(dirname "$marker")"
                echo "$workspace_dir"
                find "$workspace_dir" \( -name BUILD -o -name BUILD.bazel \) -exec dirname {} \;
            done
    ) | sed 's#^\./##'
}

# Update .bazelrc
update_bazelrc() {
    local packages
    packages=$(found_packages | sort -u)

    local start_marker="# GENERATED_DELETED_PACKAGES_START"
    local end_marker="# GENERATED_DELETED_PACKAGES_END"

    # Create a temporary file
    local tmpfile
    tmpfile=$(mktemp)

    # Write the content before the start marker
    sed "/$start_marker/q" "$BAZELRC" > "$tmpfile"

    # Write the generated packages
    echo "$start_marker" >> "$tmpfile"
    for pkg in $packages; do
        echo "common --deleted_packages=$pkg" >> "$tmpfile"
    done
    echo "$end_marker" >> "$tmpfile"

    # Write the content after the end marker
    sed "1,/$end_marker/d" "$BAZELRC" >> "$tmpfile"

    # Replace the original file
    mv "$tmpfile" "$BAZELRC"
}

update_bazelrc

#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]]; then
    readonly out="${BUILD_WORKSPACE_DIRECTORY}/{{src_out}}"
else
    exit 1
fi

# uv lock doesn't support --output-file, so we let it write uv.lock
# in the project directory, then copy it to the expected output path.
project_dir="$(dirname "$out")"
"{{args}}" --directory "$project_dir" "$@"
cp "$project_dir/uv.lock" "$out"

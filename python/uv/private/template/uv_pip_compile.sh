#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]]; then
    readonly out="${BUILD_WORKSPACE_DIRECTORY}/{{src_out}}"
    exec "{{args}}" --output-file "$out" "$@"
fi

# Build action mode: seed the output with the source file, then run
# the full command (which includes --output-file from the action args).
readonly out="{{out}}"
if [[ -f "{{src_out}}" ]]; then
    cp "{{src_out}}" "$out"
fi
exec "$@"

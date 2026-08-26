#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]]; then
    exec "{{args}}" "$@"
fi

# Build action mode
readonly out="{{out}}"
if [[ -f "{{src_out}}" ]]; then
    cp "{{src_out}}" "$out"
fi
if [[ -e "{{project_lock}}" ]]; then
    rm -f "{{project_lock}}"
fi
mkdir -p "$(dirname "{{project_lock}}")"
ln -s "$(pwd)"/"$out" "{{project_lock}}"
exec "$@"

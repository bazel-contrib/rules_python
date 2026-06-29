#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]]; then
    exec "{{args}}" "$@"
fi

# Build action mode
#
# If the uv.lock exists, remove because the existing uv.lock file is read-only, then symlink so
# that we can reuse the existing contents and not do a full relock all the time. If
# nothing exists, just symlink.
#
# On Windows we do it with file copies:
# 1. If the file exists:
#    1. Copy the current file to out.
#    2. Rm the existing file
#    3. Copy the contents back
#    4. Run uv
#    5. Copy the contents to out.
# 1. If the current uv.lock does not exist yet
#    1. Run uv
#    2. Copy the contents to out.
readonly out="{{out}}"
if [[ -f "{{src_out}}" ]]; then
    cp "{{src_out}}" "$out"
    rm "{{src_out}}"
    ln -s "$(pwd)"/"$out" "{{src_out}}"
else
    ln -s "$(pwd)"/"$out" "{{src_out}}"
fi
exec "$@"

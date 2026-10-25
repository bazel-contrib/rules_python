#!/usr/bin/env bash
set -euo pipefail

# Handle `bazel run` mode
if [[ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]]; then
    # `uv lock` has no flag to specify the lockfile path: it always reads and
    # writes `uv.lock` inside the project directory (`{{project_lock}}`
    # relative to `pwd`, where `pyproject.toml` resides).
    #
    # When `bazel run` executes this script, its `pwd` is in the runfiles
    # directory. While runfiles should be treated as read-only copies of the
    # underlying files, local execution is typically a symlink to the original,
    # writable, file. We exploit that to avoid having to copy the entire
    # directory structure to a writable location.
    readonly out="${BUILD_WORKSPACE_DIRECTORY}/{{src_out}}"
    if [[ -w "{{project_lock}}" && "{{project_lock}}" -ef "$out" ]]; then
        exec "{{args}}" "$@"
    fi

    # Handle the case when the output file isn't a writable symlink back to the
    # original file (e.g. when the lockfile does not exist yet, runfiles are not
    # writable symlinks, or a custom `out` filename is used) by staging the
    # runfiles tree into a temporary writable directory.
    readonly orig_dir="$(pwd)"
    readonly runfiles_dir="$(cd .. && pwd)"
    readonly tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT
    for entry in "$runfiles_dir"/*; do
        if [[ "$(basename "$entry")" != "_main" ]]; then
            ln -s "$entry" "$tmp_dir/$(basename "$entry")"
        fi
    done
    cp -RP "$orig_dir" "$tmp_dir/_main"
    find "$tmp_dir/_main" -type d -exec chmod u+w {} +
    cd "$tmp_dir/_main"
    rm -f "{{project_lock}}"
    mkdir -p "$(dirname "{{project_lock}}")"
    mkdir -p "$(dirname "$out")"
    ln -s "$out" "{{project_lock}}"
    "{{args}}" "$@"
    exit $?
fi

# Build action mode
#
# If the uv.lock exists, remove because the existing uv.lock file is read-only,
# then symlink so that we can reuse the existing contents and not do a full
# relock all the time. If nothing exists, just symlink.
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
fi
if [[ -e "{{project_lock}}" ]]; then
    rm -f "{{project_lock}}"
fi
mkdir -p "$(dirname "{{project_lock}}")"
ln -s "$(pwd)"/"$out" "{{project_lock}}"
exec "$@"

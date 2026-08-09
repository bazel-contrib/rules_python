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
cp_srcs=(
    "$SRCS"
)
# Copy all of the sources under a new directory, so that `directory` arg is working
# as expected and we can reroot the sources if needed. This also is a starting point
# to get the workspaces working properly in the sandbox - with this copying of sources
# we can remap the paths if needed, but that would require another attribute.
for src in "${cp_srcs[@]}"; do
    # First create a dir if it does not exist
    mkdir -p "$(dirname "{{rootdir}}/$src")"
    # Then copy the source to the dir
    cp -v "$src" "{{rootdir}}/$src"
done
exec "$@"

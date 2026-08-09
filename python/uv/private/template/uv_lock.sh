#!/usr/bin/env bash
set -euxo pipefail

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
readonly out="{{out}}"
if [[ -f "{{src_out}}" ]]; then
    cp "{{src_out}}" "$out"
    mkdir -p "$(dirname "{{rootdir}}/{{src_out}}")"
    ln -s "$(pwd)"/"$out" "{{rootdir}}/{{src_out}}"
else
    mkdir -p "$(dirname "{{rootdir}}/{{src_out}}")"
    ln -s "$(pwd)"/"$out" "{{rootdir}}/{{src_out}}"
fi
exec "$@"

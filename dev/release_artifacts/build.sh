#!/usr/bin/env bash
# Builds //dev/release_artifacts:artifacts_for_release for the platform with
# the Rust target triple TRIPLE; see dev/platforms. The target applies the
# release settings for the platform's OS and libc; see release_files.bzl. In
# GitHub Actions, the paths of the built files, relative to the workspace root,
# are set as the step's `files` output, one per line.
#
# Usage: dev/release_artifacts/build.sh EMBED_LABEL TRIPLE
set -euo pipefail

embed_label="$1"
triple="$2"

# The paths below are relative to the workspace root.
cd "$(dirname "$0")/../.."

if [[ "$triple" == "linux" ]]; then
  build_args=(//dev/release_artifacts:cross_compiled_artifacts)
  manifest="bazel-bin/dev/release_artifacts/cross_compiled_artifacts.txt"
elif ! grep -qF "name = \"$triple\"," dev/platforms/BUILD.bazel; then
  # Fail for a triple without a platform: it's the caller's mistake, unlike a
  # failed build, which only warns.
  echo "::error::dev/platforms has no $triple platform"
  exit 1
else
  build_args=(
    --platforms="//dev/platforms:$triple"
    //dev/release_artifacts:artifacts_for_release
  )
  manifest="bazel-bin/dev/release_artifacts/artifacts_for_release.txt"
fi

# Keep Git Bash on Windows from rewriting `//foo` labels into paths.
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

if ! bazel build --verbose_failures --compilation_mode=opt --stamp \
    --embed_label="$embed_label" "${build_args[@]}"; then
  # Releases don't use the files yet, so don't fail the release over them.
  echo "::warning::Building the release artifacts failed. Releases don't use them yet."
  exit 0
fi

# The target lists the paths of its files in a manifest; see release_files.bzl.
# Copy them into a single directory so upload-artifact strips the directory
# prefix instead of preserving per-platform bazel-out/<cfg> subdirectories.
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  rm -rf release-artifacts
  mkdir -p release-artifacts
  while IFS= read -r file; do
    cp "$file" release-artifacts/
  done < "$manifest"
  echo "files=release-artifacts/*" >> "$GITHUB_OUTPUT"
fi

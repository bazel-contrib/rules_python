#!/usr/bin/env bash
# Checks that the files built by build.sh don't require a newer OS than users
# may have. Only Linux and macOS files are checked.
#
# Usage: dev/release_artifacts/verify.sh TRIPLE
set -euo pipefail

triple="$1"

# The paths below are relative to the workspace root.
cd "$(dirname "$0")/../.."

# The target lists the paths of its files in a manifest; see release_files.bzl.
while IFS= read -r bin; do
  case "$triple" in
    *-linux-gnu)
      linkage="$(file "$bin")"
      if [[ "$linkage" != *"statically linked"* &&
            "$linkage" != *"static-pie linked"* ]]; then
        echo "::error::$bin isn't statically linked: $linkage"
        exit 1
      fi
      ;;
    *-apple-darwin)
      minos="$(otool -l "$bin" | awk '
        $2 == "LC_BUILD_VERSION" || $2 == "LC_VERSION_MIN_MACOSX" { found = 1 }
        found && minos == "" && ($1 == "minos" || $1 == "version") { minos = $2 }
        END { print minos }
      ')"
      if [[ -z "$minos" || "${minos%%.*}" -gt 11 ]]; then
        echo "::error::$bin requires macOS ${minos:-<unknown>}; expected 11 or lower"
        exit 1
      fi
      ;;
  esac
done < bazel-bin/dev/release_artifacts/artifacts_for_release.txt

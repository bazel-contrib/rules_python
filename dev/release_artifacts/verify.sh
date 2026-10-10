#!/usr/bin/env bash
# Checks the files built by build.sh for the platform with the Rust target
# triple TRIPLE: that Linux files are statically linked for the right CPU, and
# that macOS files don't require a newer macOS than users may have. Windows
# files aren't checked.
#
# Usage: dev/release_artifacts/verify.sh TRIPLE
set -euo pipefail

triple="$1"

# The paths below are relative to the workspace root.
cd "$(dirname "$0")/../.."

# The target lists the paths of its files in a manifest; see release_files.bzl.
while IFS= read -r bin; do
  case "$triple" in
    *-linux-*)
      info="$(file -L -b "$bin")"
      if [[ "$info" != *"statically linked"* && "$info" != *"static-pie linked"* ]]; then
        echo "::error::$bin isn't statically linked: $info"
        exit 1
      fi
      # Some Linux files are cross-compiled, so check that they're for the
      # right CPU.
      case "$triple" in
        aarch64-*) cpu="ARM aarch64" ;;
        x86_64-*) cpu="x86-64" ;;
        *)
          echo "::error::$bin: no CPU check for $triple"
          exit 1
          ;;
      esac
      if [[ "$info" != *", $cpu,"* ]]; then
        echo "::error::$bin isn't for $cpu: $info"
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
    *-windows-*) ;; # Not checked.
    *)
      echo "::error::$bin: no checks for $triple"
      exit 1
      ;;
  esac
done < bazel-bin/dev/release_artifacts/artifacts_for_release.txt

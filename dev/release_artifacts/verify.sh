#!/usr/bin/env bash
# Checks the files built by build.sh for the platform with the Rust target
# triple TRIPLE: that Linux files are statically linked, that Linux and Windows
# files are for the right CPU, and that macOS files don't require a newer macOS
# than users may have.
#
# Usage: dev/release_artifacts/verify.sh TRIPLE
set -euo pipefail

triple_arg="$1"

# The paths below are relative to the workspace root.
cd "$(dirname "$0")/../.."

if [[ "$triple_arg" == "linux" ]]; then
  manifest="bazel-bin/dev/release_artifacts/cross_compiled_artifacts.txt"
else
  manifest="bazel-bin/dev/release_artifacts/artifacts_for_release.txt"
fi

# The target lists the paths of its files in a manifest; see release_files.bzl.
while IFS= read -r bin; do
  if [[ "$triple_arg" == "linux" ]]; then
    name="${bin##*/}"
    triple="${name#*-}"
  else
    triple="$triple_arg"
  fi
  case "$triple" in
    *-linux-*)
      info="$(file -L -b "$bin")"
      if [[ "$info" != *"statically linked"* && "$info" != *"static-pie linked"* ]]; then
        echo "::error::$bin isn't statically linked: $info"
        exit 1
      fi
      # Most Linux files are cross-compiled, so check that they're for the
      # right CPU, as `file` describes it. `cpu` is a glob because file 5.46
      # renamed "Intel 80386" to "Intel i386".
      case "$triple" in
        aarch64-*) cpu="ARM aarch64" ;;
        armv7-*) cpu="ARM" ;;
        i686-*) cpu="Intel *386" ;;
        powerpc64le-*) cpu="64-bit PowerPC or cisco 7500" ;;
        riscv64gc-*) cpu="UCB RISC-V" ;;
        x86_64-*) cpu="x86-64" ;;
        *)
          echo "::error::$bin: no CPU check for $triple"
          exit 1
          ;;
      esac
      pattern="*, $cpu,*"
      # shellcheck disable=SC2053 # The pattern is a glob.
      if [[ "$info" != $pattern ]]; then
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
    *-windows-*)
      # The i686 files are cross-compiled, so check that they're for the right
      # CPU. PE files start with "MZ", and the PE header's offset is at 0x3c.
      # The machine type follows the header's 4-byte signature. Like PE, the
      # runners are little-endian, and od uses the host's byte order.
      if [[ "$(head -c2 "$bin")" != MZ ]]; then
        echo "::error::$bin isn't a PE file"
        exit 1
      fi
      pe="$(od -An -tu4 -j60 -N4 "$bin" | tr -d ' ')"
      machine="$(od -An -tx2 -j"$((pe + 4))" -N2 "$bin" | tr -d ' ')"
      case "$triple" in
        aarch64-*) want="aa64" ;;
        i686-*) want="014c" ;;
        x86_64-*) want="8664" ;;
        *)
          echo "::error::$bin: no CPU check for $triple"
          exit 1
          ;;
      esac
      if [[ "$machine" != "$want" ]]; then
        echo "::error::$bin's PE machine type is 0x$machine, not 0x$want"
        exit 1
      fi
      ;;
    *)
      echo "::error::$bin: no checks for $triple"
      exit 1
      ;;
  esac
done < "$manifest"

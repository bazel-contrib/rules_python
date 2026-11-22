#!/usr/bin/env bash
# --- begin runfiles.bash initialization v3 ---
# Copy-pasted from the Bazel Bash runfiles library v3.
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  { echo>&2 "ERROR: cannot find $f"; exit 1; }; f=; set -e
# --- end runfiles.bash initialization v3 ---
set +e

bin=$(rlocation "$BIN_RLOCATION")
if [[ -z "$bin" ]]; then
  echo "Unable to locate test binary: $BIN_RLOCATION"
  exit 1
fi

# Checks that the output matches a pattern.
#
# Modifies:
#   Creates EXPECTATION_FAILED in the working directory on mismatch.
function expect_match() {
  local expected_pattern=$1
  local actual=$2
  if ! (echo "$actual" | grep "$expected_pattern" ) >/dev/null; then
    echo "expected to match: $expected_pattern"
    echo "===== actual START ====="
    echo "$actual"
    echo "===== actual END ====="
    echo
    touch EXPECTATION_FAILED
    return 1
  fi
}

# Converts a Windows path to a Unix one under MSYS, so that bash can use it.
function to_unix() {
  cygpath --unix "$1"
}

# Use hard links, junctions or copies instead of symlinks for the venv that
# is created at runtime, like without the privilege to create symlinks.
# tr: remove the CR of the CRLF line endings of the output on Windows.
venvs_root=$(mktemp --directory "$(to_unix "$TEST_TMPDIR")/venvs_root.XXXXXX")
actual=$(RULES_PYTHON_TESTING_DISABLE_SYMLINKS=1 RULES_PYTHON_EXTRACT_ROOT="$venvs_root" "$bin" | tr --delete '\r')
expect_match "Hello" "$actual"
# Match the name only, because the path is a Windows path on Windows.
expect_match "sys.executable:.*$(basename "$venvs_root")" "$actual"
expect_match "sys.executable is symlink: False" "$actual"

# Without RULES_PYTHON_EXTRACT_ROOT, the venv is removed after the run, which
# must work for read-only Bazel outputs that are hard linked or copied, and must
# not make the hard linked outputs writable.
runfiles=$(to_unix "${RUNFILES_DIR:-$TEST_SRCDIR}")
# -L: follow the runfiles symlinks to the Bazel outputs.
read_only_before=$(find -L "$runfiles" -type f ! -writable | sort)
if [[ -z "$read_only_before" ]]; then
  echo "expected read-only files in the runfiles: $runfiles"
  touch EXPECTATION_FAILED
fi
actual=$(RULES_PYTHON_TESTING_DISABLE_SYMLINKS=1 "$bin" | tr --delete '\r')
expect_match "Hello" "$actual"
expect_match "sys.executable is symlink: False" "$actual"
venv=$(to_unix "$(echo "$actual" | grep "^sys.prefix:" | cut --delimiter=' ' --fields=2-)")
if [[ -z "$venv" || -e "$venv" ]]; then
  echo "expected the venv to be removed: $venv"
  touch EXPECTATION_FAILED
fi
read_only_after=$(find -L "$runfiles" -type f ! -writable | sort)
if [[ "$read_only_before" != "$read_only_after" ]]; then
  echo "expected the read-only runfiles to be unchanged"
  diff <(echo "$read_only_before") <(echo "$read_only_after")
  touch EXPECTATION_FAILED
fi

# Exit if any of the expects failed
[[ ! -e EXPECTATION_FAILED ]]

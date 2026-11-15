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

bin=$(rlocation $BIN_RLOCATION)
if [[ -z "$bin" ]]; then
  echo "Unable to locate test binary: $BIN_RLOCATION"
  exit 1
fi

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

# Use hard links, junctions or copies instead of symlinks for the venv that
# is created at runtime, like on Windows without the privilege to create
# symlinks.
venvs_root=$(mktemp -d)
actual=$(RULES_PYTHON_TESTING_DISABLE_SYMLINKS=1 RULES_PYTHON_EXTRACT_ROOT=$venvs_root $bin)
expect_match "Hello" "$actual"
expect_match "sys.executable:.*$venvs_root" "$actual"

venv_python=$(echo "$actual" | grep "^sys.executable:" | cut -d' ' -f2-)
if [[ -L "$venv_python" ]]; then
  echo "expected the venv interpreter not to be a symlink: $venv_python"
  touch EXPECTATION_FAILED
fi

# Without RULES_PYTHON_EXTRACT_ROOT, the venv is removed after the run, which
# must work for read-only copies of Bazel outputs too.
actual=$(RULES_PYTHON_TESTING_DISABLE_SYMLINKS=1 $bin)
expect_match "Hello" "$actual"
venv_python=$(echo "$actual" | grep "^sys.executable:" | cut -d' ' -f2-)
venv=$(dirname "$(dirname "$venv_python")")
if [[ -e "$venv" ]]; then
  echo "expected the venv to be removed: $venv"
  touch EXPECTATION_FAILED
fi

# Exit if any of the expects failed
[[ ! -e EXPECTATION_FAILED ]]

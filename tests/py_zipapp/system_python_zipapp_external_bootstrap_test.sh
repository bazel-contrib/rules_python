#!/usr/bin/env bash

set -xeuo pipefail

# This test expects ZIPAPP env var to point to the zipapp file.
if [[ -z "${ZIPAPP:-}" ]]; then
  echo "ZIPAPP env var not set"
  exit 1
fi

# On Windows, the executable file is an exe, and the .zip is a sibling
# output.
ZIPAPP="${ZIPAPP/.exe/.zip}"

export RULES_PYTHON_BOOTSTRAP_VERBOSE=1

# We're testing the invocation of `__main__.py`, so we have to
# manually pass the zipapp to python.
echo "Running zipapp using an automatic temp directory..."
"$PYTHON" "$ZIPAPP"

echo "Running zipapp with extract root set..."
export RULES_PYTHON_EXTRACT_ROOT="${TEST_TMPDIR:-/tmp}/extract_root_test"
"$PYTHON" "$ZIPAPP"

# Verify that the directory was created
if [[ ! -d "$RULES_PYTHON_EXTRACT_ROOT" ]]; then
  echo "Error: Extract root directory $RULES_PYTHON_EXTRACT_ROOT was not created!"
  exit 1
fi

# The extract dir is _main/tests/py_zipapp/system_python_zipapp
# The new structure should be $RULES_PYTHON_EXTRACT_ROOT/_main/tests/py_zipapp/system_python_zipapp/<hash>/runfiles
# We check that there is a subdirectory under the expected extract dir.
EXTRACT_DIR="_main/tests/py_zipapp/system_python_zipapp"
if [[ ! -d "$RULES_PYTHON_EXTRACT_ROOT/$EXTRACT_DIR" ]]; then
  echo "Error: Extract directory $RULES_PYTHON_EXTRACT_ROOT/$EXTRACT_DIR was not created!"
  exit 1
fi

# Check for the extra hash component.
# Before the change, $RULES_PYTHON_EXTRACT_ROOT/$EXTRACT_DIR/runfiles would exist.
# After the change, $RULES_PYTHON_EXTRACT_ROOT/$EXTRACT_DIR/<hash>/runfiles will exist.
# We look for any directory under $EXTRACT_DIR that contains 'runfiles'.
if ! find "$RULES_PYTHON_EXTRACT_ROOT/$EXTRACT_DIR" -maxdepth 2 -name runfiles | grep -q "runfiles"; then
  echo "Error: Could not find 'runfiles' directory under $RULES_PYTHON_EXTRACT_ROOT/$EXTRACT_DIR"
  exit 1
fi

# Specifically check that there's an intermediate directory between EXTRACT_DIR and runfiles
# find ... -mindepth 2 -maxdepth 2 -name runfiles should find it only if there is an intermediate dir.
if ! find "$RULES_PYTHON_EXTRACT_ROOT/$EXTRACT_DIR" -mindepth 2 -maxdepth 2 -name runfiles | grep -q "runfiles"; then
  echo "Error: 'runfiles' directory is not at the expected depth. Missing APP_HASH component?"
  exit 1
fi

echo "Running zipapp with extract root set a second time..."
"$PYTHON" "$ZIPAPP"

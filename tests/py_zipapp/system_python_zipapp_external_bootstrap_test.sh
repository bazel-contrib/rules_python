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
# We use glob expansion to check for the expected depth.
# Note: [ -d ... ] expands globs, while [[ -d ... ]] does not.
if [ ! -d "$RULES_PYTHON_EXTRACT_ROOT/$EXTRACT_DIR"/*/runfiles ]; then
  echo "Error: Could not find 'runfiles' directory at expected depth $RULES_PYTHON_EXTRACT_ROOT/$EXTRACT_DIR/*/runfiles"
  exit 1
fi

echo "Running zipapp with extract root set a second time..."
"$PYTHON" "$ZIPAPP"

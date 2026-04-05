#!/usr/bin/env bash
# Verify that the RULES_PYTHON_EXTRACT_ROOT env variable is respected.

set -euo pipefail

export RULES_PYTHON_EXTRACT_ROOT="${TEST_TMPDIR:-/tmp}/extract_root_test"

echo "Running zipapp the first time..."
"$ZIPAPP"

# Verify that the directory was created
if [[ ! -d "$RULES_PYTHON_EXTRACT_ROOT" ]]; then
  echo "Error: Extract root directory $RULES_PYTHON_EXTRACT_ROOT was not created!"
  exit 1
fi

# Run a second time to ensure it can re-extract successfully.
echo "Running zipapp the second time..."
"$ZIPAPP"

echo "Success!"

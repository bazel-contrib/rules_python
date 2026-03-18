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
"$PYTHON" "$ZIPAPP"

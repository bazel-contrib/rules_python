#!/usr/bin/env bash

set -euo pipefail

# This test expects ZIPAPP env var to point to the zipapp file.
if [[ -z "${ZIPAPP:-}" ]]; then
  echo "ZIPAPP env var not set"
  exit 1
fi

# We're testing the invocation of `__main__.py`, so we have to
# manually pass the zipapp to python.
"$PYTHON" "$ZIPAPP"

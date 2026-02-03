#!/usr/bin/env bash

set -euo pipefail

# This test expects ZIPAPP env var to point to the zipapp file.
if [[ -z "${ZIPAPP:-}" ]]; then
  echo "ZIPAPP env var not set"
  exit 1
fi

echo "Running zipapp: $ZIPAPP"
# We use python3 to run the zipapp.
# This ensures that the zipapp (which is a zip file with __main__.py)
# is valid and executable by python.
python3 "$ZIPAPP"

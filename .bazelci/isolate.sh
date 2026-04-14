#!/usr/bin/env bash
set -euo pipefail

MODULE_DIR="${1:-}"

if [[ -z "${MODULE_DIR}" ]]; then
  echo "Usage: $0 <module_directory>"
  exit 1
fi

# Find the repository root assuming this script is in .bazelci/
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

cd "${REPO_ROOT}"

echo "Removing files outside of ${MODULE_DIR} to simulate BCR environment..."
find . -maxdepth 1 -mindepth 1 \
  ! -name "${MODULE_DIR}" \
  ! -name ".git" \
  ! -name ".bazelci" \
  -exec rm -rf '{}' +

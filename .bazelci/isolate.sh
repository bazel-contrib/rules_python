#!/usr/bin/env bash
set -euo pipefail

module_dir="${1:-}"

if [[ -z "${module_dir}" ]]; then
  echo "Usage: $0 <module_directory>"
  exit 1
fi

# Find the repository root assuming this script is in .bazelci/
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(dirname "${script_dir}")"

cd "${repo_root}"

if [[ ! -f "MODULE.bazel" ]]; then
  echo "Error: MODULE.bazel not found in ${repo_root}. Are you sure this is the repo root?"
  exit 1
fi

if [[ ! -d "${module_dir}" ]]; then
  echo "Error: Module directory '${module_dir}' not found in ${repo_root}."
  exit 1
fi

echo "Removing files outside of ${module_dir} to simulate BCR environment..."
find . -maxdepth 1 -mindepth 1 \
  ! -name "${module_dir}" \
  ! -name ".git" \
  ! -name ".bazelci" \
  -exec rm -rf '{}' +

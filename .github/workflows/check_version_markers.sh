#!/usr/bin/env bash

set -o nounset
set -o pipefail
set -o errexit

set -x

TAG=${1:-}
if [ -n "$TAG" ]; then
  # If the workflow checks out one commit, but is releasing another
  git fetch origin tag "$TAG"
  # Update our local state so the grep command below searches what we expect
  git checkout "$TAG"
fi

grep_exit_code=0
# Exclude dot directories, specifically, this file so that we don't
# find the substring we're looking for in our own file.
# Exclude CONTRIBUTING.md, RELEASING.md because they document how to use these strings.
grep --exclude=CONTRIBUTING.md \
  --exclude=RELEASING.md \
  --exclude=release.py \
  --exclude=release_test.py \
  --exclude-dir=.* \
  VERSION_NEXT_ -r || grep_exit_code=$?

if [[ $grep_exit_code -eq 0 ]]; then
  echo
  echo "Found VERSION_NEXT markers indicating version needs to be specified"
  exit 1
fi

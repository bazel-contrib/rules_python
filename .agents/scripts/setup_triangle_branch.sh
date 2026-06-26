#!/bin/bash
# Helper script to set up upstream tracking for fork-and-PR workflow.
set -e

# Detect current branch if not provided as argument
BRANCH_NAME="${1:-$(git symbolic-ref --short HEAD)}"

if [ -z "$BRANCH_NAME" ]; then
  echo "Error: Could not detect current branch name." >&2
  exit 1
fi

echo "Setting up upstream tracking for branch: $BRANCH_NAME"

# 1. Set the pull/fetch behavior to track the canonical repo's main branch
git config --local "branch.${BRANCH_NAME}.remote" upstream
git config --local "branch.${BRANCH_NAME}.merge" refs/heads/main

# 2. Override the destination remote for pushing
git config --local "branch.${BRANCH_NAME}.pushRemote" origin

# 3. Defend against global push.default settings (ensure it pushes to current branch name)
git config --local push.default current

echo "Successfully configured upstream/main tracking and origin pushRemote for $BRANCH_NAME!"

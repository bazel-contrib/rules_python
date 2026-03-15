#!/bin/bash
set -euo pipefail

verify_output() {
  local OUTPUT_FILE=$1

  # Extract the RULES_PYTHON_TESTING_RUNFILES_ROOT values
  local OUTER_RUNFILES_ROOT=$(grep "outer: RULES_PYTHON_TESTING_RUNFILES_ROOT" "$OUTPUT_FILE" | sed "s/outer: RULES_PYTHON_TESTING_RUNFILES_ROOT='\(.*\)'/\1/")
  local INNER_RUNFILES_ROOT=$(grep "inner: RULES_PYTHON_TESTING_RUNFILES_ROOT" "$OUTPUT_FILE" | sed "s/inner: RULES_PYTHON_TESTING_RUNFILES_ROOT='\(.*\)'/\1/")

  echo "Outer runfiles root: $OUTER_RUNFILES_ROOT"
  echo "Inner runfiles root: $INNER_RUNFILES_ROOT"

  # Check 1: The two values are different
  if [ "$OUTER_RUNFILES_ROOT" == "$INNER_RUNFILES_ROOT" ]; then
    echo "Error: Outer and Inner runfiles roots are the same."
    exit 1
  fi

  # Check 2: Inner is not a subdirectory of Outer
  case "$INNER_RUNFILES_ROOT" in
    "$OUTER_RUNFILES_ROOT"/*)
      echo "Error: Inner runfiles root is a subdirectory of Outer's."
      exit 1
      ;;
    *)
      # This is the success case
      ;;
  esac

  echo "Verification successful."
}

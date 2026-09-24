#!/usr/bin/env bash
# A system-runtime wrapper can resolve to an interpreter with a different name.
IFS= read -r data < "$RUNFILES_DIR/$CLEANUP_WRAPPER_DATA"
[[ "$data" == "wrapper runfile" ]] || exit 91
exec "${CLEANUP_REAL_INTERPRETER:-python3}" "$@"

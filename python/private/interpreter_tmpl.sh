#!/usr/bin/env bash
set -uo pipefail

readonly TARGET_FILE="%target_file%"
MAIN_BIN=""

if [[ -n "${RUNFILES_MANIFEST_FILE:-}" && \
      -f "${RUNFILES_MANIFEST_FILE}" ]]; then
  MAIN_BIN="$(grep -F -m1 "${TARGET_FILE} " \
    "${RUNFILES_MANIFEST_FILE}" | cut -f2- -d' ')"
fi
if [[ -z "${MAIN_BIN:-}" ]]; then
  if [[ -n "${RUNFILES_DIR:-}" && -e "${RUNFILES_DIR}/${TARGET_FILE}" ]]; then
    MAIN_BIN="${RUNFILES_DIR}/${TARGET_FILE}"
  elif [[ -f "$0.runfiles_manifest" ]]; then
    MAIN_BIN="$(grep -F -m1 "${TARGET_FILE} " \
      "$0.runfiles_manifest" | cut -f2- -d' ')"
  elif [[ -e "$0.runfiles/${TARGET_FILE}" ]]; then
    MAIN_BIN="$0.runfiles/${TARGET_FILE}"
  elif [[ -e "${TARGET_FILE}" ]]; then
    MAIN_BIN="${TARGET_FILE}"
  fi
fi

if [[ -z "${MAIN_BIN:-}" || ! -e "${MAIN_BIN}" ]]; then
  echo "ERROR: interpreter executable not found: ${MAIN_BIN:-<empty>}" \
    "(from ${TARGET_FILE})" >&2
  exit 1
fi

if [[ -z "${PYTHONHOME:-}" ]]; then
  export PYTHONHOME="$(dirname "$(dirname "$MAIN_BIN")")"
fi

exec "${MAIN_BIN}" "$@"

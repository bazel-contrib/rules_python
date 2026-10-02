#!/usr/bin/env sh
set -eu

PYTHON_EXE_RUNFILES_PATH="%python_exe_runfiles_path%"
MAIN_BIN=""

if [ -n "${RUNFILES_DIR:-}" ] && \
   [ -e "${RUNFILES_DIR}/${PYTHON_EXE_RUNFILES_PATH}" ]; then
  MAIN_BIN="${RUNFILES_DIR}/${PYTHON_EXE_RUNFILES_PATH}"
elif [ -n "${RUNFILES_MANIFEST_FILE:-}" ] && \
     [ -f "${RUNFILES_MANIFEST_FILE}" ]; then
  MAIN_BIN="$(grep -F -m1 "${PYTHON_EXE_RUNFILES_PATH} " \
    "${RUNFILES_MANIFEST_FILE}" 2>/dev/null | cut -f2- -d' ' || true)"
elif [ -e "$0.runfiles/${PYTHON_EXE_RUNFILES_PATH}" ]; then
  MAIN_BIN="$0.runfiles/${PYTHON_EXE_RUNFILES_PATH}"
elif [ -f "$0.runfiles_manifest" ]; then
  MAIN_BIN="$(grep -F -m1 "${PYTHON_EXE_RUNFILES_PATH} " \
    "$0.runfiles_manifest" 2>/dev/null | cut -f2- -d' ' || true)"
elif [ -f "$0.exe.runfiles_manifest" ]; then
  MAIN_BIN="$(grep -F -m1 "${PYTHON_EXE_RUNFILES_PATH} " \
    "$0.exe.runfiles_manifest" 2>/dev/null | cut -f2- -d' ' || true)"
fi

if [ -z "${MAIN_BIN:-}" ] || [ ! -e "${MAIN_BIN}" ]; then
  echo "ERROR: interpreter executable not found: ${MAIN_BIN:-<empty>}" \
    "(from ${PYTHON_EXE_RUNFILES_PATH})" >&2
  exit 1
fi

# Determine PYTHONHOME (installation prefix containing lib/pythonX.Y).
# We must set PYTHONHOME to point to the runfiles directory because runfiles
# provides the unified merge of source files and generated files needed by
# the standard library and runtime.
# In standard POSIX layouts, MAIN_BIN is at <prefix>/bin/python3, so the prefix
# is $(dirname $(dirname "$MAIN_BIN")). In flat toolchain layouts where the
# binary is a sibling to lib, the prefix is $(dirname "$MAIN_BIN").
if [ -d "$(dirname "$MAIN_BIN")/lib" ]; then
  PYTHONHOME="$(dirname "$MAIN_BIN")"
else
  PYTHONHOME="$(dirname "$(dirname "$MAIN_BIN")")"
fi
if [ -d "$PYTHONHOME" ]; then
  PYTHONHOME="$(cd "$PYTHONHOME" && pwd)"
fi
export PYTHONHOME

exec "${MAIN_BIN}" "$@"


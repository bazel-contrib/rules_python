#!/usr/bin/env bash

set -e

if [[ -n "${RULES_PYTHON_BOOTSTRAP_VERBOSE:-}" ]]; then
  set -x
fi

# runfiles-root-relative path
BUNDLED_PYEXE_PATH="%BUNDLED_PYEXE_PATH%"
# Absolute path or single word
EXTERNAL_PYEXE_PATH="%EXTERNAL_PYEXE_PATH%"
# runfiles-root-relative path
STAGE2_BOOTSTRAP="%STAGE2_BOOTSTRAP%"
EXTRACT_DIR="%EXTRACT_DIR%"
ZIP_HASH="%ZIP_HASH%"
declare -a INTERPRETER_ARGS_FROM_TARGET=(
%INTERPRETER_ARGS%
)

declare -a interpreter_env
declare -a interpreter_args
declare -a additional_interpreter_args

if [[ -z "${PYTHONSAFEPATH+x}" ]]; then
  # ${FOO-WORD} expands to WORD if $FOO is undefined, and $FOO otherwise
  interpreter_env+=("PYTHONSAFEPATH=${PYTHONSAFEPATH-1}")
fi


if [[ -n "${RULES_PYTHON_ADDITIONAL_INTERPRETER_ARGS}" ]]; then
  read -a additional_interpreter_args <<< "${RULES_PYTHON_ADDITIONAL_INTERPRETER_ARGS}"
  interpreter_args+=("${additional_interpreter_args[@]}")
  unset RULES_PYTHON_ADDITIONAL_INTERPRETER_ARGS
fi


cleanup_zip_dir=""
if [[ -n "$RULES_PYTHON_EXTRACT_ROOT" ]]; then
  zip_dir="$RULES_PYTHON_EXTRACT_ROOT/$EXTRACT_DIR/$ZIP_HASH"
  if [[ ! -e "$zip_dir/__main__.py" ]]; then
    mkdir -p "$zip_dir"
    # Unzip emits a warning and exits 1 with the prelude
    ( unzip -q -d "$zip_dir" "$0" 2>/dev/null || true )
  fi
else
  # NOTE: Macs have an old version of mktemp, so we must use only the
  # minimal functionality of it.
  zip_dir=$(mktemp -d)
  # Unzip emits a warning and exits 1 with the prelude
  ( unzip -q -d "$zip_dir" "$0" 2>/dev/null || true )
  if [[ -n "$zip_dir" && -z "${RULES_PYTHON_BOOTSTRAP_VERBOSE:-}" ]]; then
    cleanup_zip_dir=1
    trap 'rm -fr "$zip_dir"' EXIT
  fi
fi

export RUNFILES_DIR="$zip_dir/runfiles"
if [[ ! -d "$RUNFILES_DIR" ]]; then
  echo "Runfiles dir not found: zip extraction likely failed" 1>&2
  echo "Run with RULES_PYTHON_BOOTSTRAP_VERBOSE=1 to aid debugging" 1>&2
  exit 1
fi

if [[ -n "$BUNDLED_PYEXE_PATH" ]]; then
  python_exe="$RUNFILES_DIR/$BUNDLED_PYEXE_PATH"
else
  python_exe="$EXTERNAL_PYEXE_PATH"
fi

command=(
  env
  "${interpreter_env[@]}"
  "$python_exe"
  "-XRULES_PYTHON_ZIP_DIR=$zip_dir"
  "${interpreter_args[@]}"
  "${INTERPRETER_ARGS_FROM_TARGET[@]}"
  "$RUNFILES_DIR/$STAGE2_BOOTSTRAP"
  "$@"
)

# Prints an identifier for a running process that changes if the PID is reused,
# or nothing once the process has exited. A zombie counts as exited, so it
# doesn't matter whether the caller has reaped it yet.
process_identity() {
  local stat fields
  if [[ -r "/proc/$1/stat" ]]; then
    stat=$(< "/proc/$1/stat") || return 0
    # The command name is in parentheses and may contain spaces, so split the
    # fields after the last ")": field 3 (state) through field 22 (start time).
    read -r -a fields <<< "${stat##*) }"
    if [[ "${fields[0]}" != "Z" ]]; then
      echo "${fields[19]}"
    fi
  elif command -v ps >/dev/null 2>&1; then
    stat=$(ps -o stat=,lstart= -p "$1" 2>/dev/null)
    stat="${stat#"${stat%%[![:space:]]*}"}"
    if [[ -n "$stat" && "$stat" != Z* ]]; then
      echo "${stat#* }"
    fi
  elif kill -0 "$1" 2>/dev/null; then
    echo "running"
  fi
}

if [[ -n "$cleanup_zip_dir" ]]; then
  # exec replaces this shell, so the EXIT trap can't remove the extracted files.
  # Instead, start a watcher that removes them once this PID, which becomes the
  # Python process, exits. Unlike the trap, this also works when the process is
  # killed with SIGKILL. The watcher is double-forked so it isn't a child of the
  # Python process, and it doesn't hold this process's stdio open. It stays in
  # the caller's process group, so it ignores the signals sent to a whole group
  # (e.g. Ctrl-C in a terminal) and exits on its own once the process is gone.
  # Unlike the implicit SIGINT ignore for background jobs, `trap ''` also
  # applies to the commands it runs.
  trap - EXIT
  launcher_pid=$$
  launcher_identity=$(process_identity "$launcher_pid")
  ( (
    trap '' INT QUIT HUP TERM
    while [[ "$(process_identity "$launcher_pid")" == "$launcher_identity" ]]; do
      sleep 1
    done
    rm -fr "$zip_dir"
  ) </dev/null >/dev/null 2>&1 & )
fi

# We use `exec` instead of a child process so that signals sent directly (e.g.
# using `kill`) to this process (the PID seen by the calling process) are
# received by the Python process. Otherwise, this process receives the signal
# and the Python process keeps running.
# See https://github.com/bazel-contrib/rules_python/issues/2043#issuecomment-2215469971
# for more information.
exec "${command[@]}"

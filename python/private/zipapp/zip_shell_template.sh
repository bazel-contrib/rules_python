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


# LINT.IfChange(process_identity)
# Prints an identifier for a running process that changes if the PID is reused,
# or nothing once the process has exited. A zombie counts as exited, so it
# doesn't matter whether the caller has reaped it yet.
process_identity() {
  local stat fields
  if [[ -r "/proc/$1/stat" ]]; then
    stat=$(< "/proc/$1/stat") || return 0
    # The command name is in parentheses and may contain spaces, so split the
    # fields after the last ")": field 3 (state) through field 22 (start time).
    # -r: raw input (no backslash escapes); -a: split into array (Bash builtin).
    read -r -a fields <<< "${stat##*) }"
    if [[ "${fields[0]}" != "Z" ]]; then
      echo "${fields[19]}"
    fi
  # -o (--format), -p (--pid): short flags for BSD/macOS ps compatibility.
  elif command -v ps >/dev/null 2>&1 &&
       stat=$(ps -o stat=,lstart= -p "$1" 2>/dev/null); then
    # Strip leading whitespace, then print lstart after the stat column.
    stat="${stat#"${stat%%[![:space:]]*}"}"
    if [[ -n "$stat" && "$stat" != Z* ]]; then
      echo "${stat#* }"
    fi
  # -0: check process existence without sending a signal.
  elif kill -0 "$1" 2>/dev/null; then
    echo "running"
  fi
}
# LINT.ThenChange(//python/private/stage1_bootstrap_template.sh:process_identity)

if [[ -n "$RULES_PYTHON_EXTRACT_ROOT" ]]; then
  zip_dir="$RULES_PYTHON_EXTRACT_ROOT/$EXTRACT_DIR/$ZIP_HASH"
  if [[ ! -e "$zip_dir/__main__.py" ]]; then
    mkdir -p "$zip_dir"
    # Unzip emits a warning and exits 1 with the prelude; -q: quiet (no long option).
    ( unzip -q -d "$zip_dir" "$0" 2>/dev/null || true )
  fi
else
  # LINT.IfChange(zip_extract_watcher)
  # NOTE: Macs have an old version of mktemp, so we must use only the
  # minimal functionality of it.
  # Short flags for BSD/macOS portability: mktemp -d (--directory),
  # rm -fr (--force --recursive), unzip -q (quiet; no long option).
  launcher_pid=$$
  launcher_identity=""
  if [[ -z "${RULES_PYTHON_BOOTSTRAP_VERBOSE:-}" ]]; then
    launcher_identity=$(process_identity "$launcher_pid")
  fi
  if [[ -n "$launcher_identity" ]]; then
    # A detached watcher creates the extraction directory, prints its path,
    # and removes the directory once this PID exits. exec below replaces this
    # shell with the Python process, which keeps the PID but not the EXIT trap.
    # Because the directory only exists once the watcher is running, it's
    # removed even if this process is killed at any point, including while
    # unzipping and with SIGKILL. The watcher is double-forked so it isn't a
    # child of the Python process, and after printing the path it doesn't hold
    # this process's stdio open. It stays in the caller's process group, so it
    # ignores the signals sent to a whole group (e.g. Ctrl-C in a terminal) and
    # exits on its own once the process is gone. Unlike the implicit SIGINT
    # ignore for background jobs, `trap ''` also applies to the commands it
    # runs. It ignores SIGPIPE because this process may be gone before it reads
    # the path.
    zip_dir=$( ( (
      trap '' INT QUIT HUP TERM PIPE
      dir=$(mktemp -d) || exit 1
      echo "$dir" || true
      exec >/dev/null
      while [[ "$(process_identity "$launcher_pid")" == "$launcher_identity" ]]; do
        sleep 1
      done
      # If this process was killed while unzipping, unzip may still be adding
      # files, so retry until the directory is gone. unzip can't create it
      # again: it extracts relative to its working directory, which is the
      # directory.
      for _ in {1..60}; do
        rm -fr "$dir" && break
        sleep 1
      done
    ) </dev/null 2>/dev/null & ) )
    if [[ -z "$zip_dir" ]]; then
      echo "Failed to create a temporary directory to extract the zip into" 1>&2
      exit 1
    fi
    # Also remove the directory right away if startup fails before exec.
    trap 'rm -fr "$zip_dir"' EXIT
  else
    # Keep the extracted files for debugging when verbose, or fall back to the
    # EXIT trap if process_identity is unavailable.
    zip_dir=$(mktemp -d)
    if [[ -n "$zip_dir" && -z "${RULES_PYTHON_BOOTSTRAP_VERBOSE:-}" ]]; then
      trap 'rm -fr "$zip_dir"' EXIT
    fi
  fi
  zip_file="$0"
  if [[ "$zip_file" != /* ]]; then
    zip_file="$PWD/$zip_file"
  fi
  # Extract relative to the directory, so that if this process is killed, an
  # orphaned unzip can't recreate the directory after the watcher removes it.
  # Unzip emits a warning and exits 1 with the prelude
  ( cd "$zip_dir" && unzip -q "$zip_file" 2>/dev/null || true )
  # LINT.ThenChange(//python/private/stage1_bootstrap_template.sh:zip_extract_watcher)
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
  "${interpreter_args[@]}"
  "${INTERPRETER_ARGS_FROM_TARGET[@]}"
  "$RUNFILES_DIR/$STAGE2_BOOTSTRAP"
  "$@"
)

# We use `exec` instead of a child process so that signals sent directly (e.g.
# using `kill`) to this process (the PID seen by the calling process) are
# received by the Python process. Otherwise, this process receives the signal
# and the Python process keeps running.
# See https://github.com/bazel-contrib/rules_python/issues/2043#issuecomment-2215469971
# for more information.
if [[ -n "${RULES_PYTHON_EXTRACT_ROOT:-}" ||
      -n "${launcher_identity:-}" ||
      -n "${RULES_PYTHON_BOOTSTRAP_VERBOSE:-}" ]]; then
  exec "${command[@]}"
else
  "${command[@]}"
  exit $?
fi

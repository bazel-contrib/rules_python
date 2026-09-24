#!/usr/bin/env bash
set -e

if [[ -n "${RULES_PYTHON_BOOTSTRAP_VERBOSE:-}" ]]; then set -x; fi

IS_ZIPFILE=%archive%
CACHE=%cache%
CACHE_NAME=%cache_name%
APP_HASH="%APP_HASH%"
APPLICATION_SPEC=%spec_shell%
BOOTSTRAP_DRIVER=%driver_shell%
STAGE2_BOOTSTRAP=%entry_shell%
BOOTSTRAP_CLEANUP=%cleanup_shell%
WORKSPACE_NAME=%workspace_shell%
INTERPRETER_KIND=%interpreter_kind%
PYTHON_BINARY_ACTUAL=%interpreter_shell%
PYTHON_BINARY=%venv_executable_shell%
RECREATE_VENV_AT_RUNTIME=%recreate%
RESOLVE_PYTHON_BINARY_AT_RUNTIME=%resolve%
declare -a INTERPRETER_ARGS_FROM_TARGET=(
%interpreter_args_shell%
)
declare -a additional_interpreter_args=()
if [[ -n "${RULES_PYTHON_ADDITIONAL_INTERPRETER_ARGS:-}" ]]; then
  read -a additional_interpreter_args <<< "$RULES_PYTHON_ADDITIONAL_INTERPRETER_ARGS"
fi
unset RULES_PYTHON_ADDITIONAL_INTERPRETER_ARGS
unset __PYVENV_LAUNCHER__

# These values describe only allocations and children owned by this invocation.
workspace=""
child=""
cancelled=0
starting_child=0
cleanup() {
  local status=$?
  trap '' TERM INT HUP QUIT
  if [[ -n "$child" ]]; then
    # Preparation handles TERM cooperatively and reaps any children it owns.
    kill -TERM %+ 2>/dev/null || true
    wait "$child" 2>/dev/null || true
  fi
  if [[ -n "$workspace" && -z "${RULES_PYTHON_BOOTSTRAP_VERBOSE:-}" ]]; then
    rm -rf "$workspace"
  fi
  exit "$status"
}
cancel() {
  cancelled=$1
  if [[ "$starting_child" == 0 ]]; then exit "$cancelled"; fi
}
own_workspace() {
  trap 'cancel 143' TERM
  trap 'cancel 130' INT
  trap 'cancel 129' HUP
  trap 'cancel 131' QUIT
  trap cleanup EXIT
  local parent=$1
  if [[ "$parent" != /* ]]; then parent="$PWD/$parent"; fi
  workspace=$(trap '' TERM INT HUP QUIT; mktemp -d "$parent/rules_python.XXXXXXXXXX")
}
run_preparer() {
  local status=0
  starting_child=1
  "$@" &
  child=$!
  starting_child=0
  if [[ "$cancelled" != 0 ]]; then exit "$cancelled"; fi
  wait "$child" || status=$?
  child=""
  return "$status"
}
find_runfiles_root() {
  local candidate="${RUNFILES_DIR:-}" filename=$1 target
  if [[ -z "$candidate" ]]; then
    case "${RUNFILES_MANIFEST_FILE:-}" in
      *.runfiles_manifest) candidate="${RUNFILES_MANIFEST_FILE%_manifest}" ;;
      *.runfiles/MANIFEST) candidate="${RUNFILES_MANIFEST_FILE%/MANIFEST}" ;;
    esac
  fi
  if [[ -n "$candidate" && -f "$candidate/$APPLICATION_SPEC" ]]; then
    RUNFILES_DIR=$candidate
    return
  fi
  unset RUNFILES_MANIFEST_FILE
  if [[ "$filename" != /* ]]; then filename="$PWD/$filename"; fi
  while true; do
    if [[ -f "$filename.runfiles/$APPLICATION_SPEC" ]]; then
      RUNFILES_DIR="$filename.runfiles"
      return
    fi
    if [[ "$filename" == *.runfiles/* ]]; then
      candidate="${filename%.runfiles/*}.runfiles"
      if [[ -f "$candidate/$APPLICATION_SPEC" ]]; then
        RUNFILES_DIR=$candidate
        return
      fi
    fi
    if [[ ! -L "$filename" ]]; then break; fi
    target=$(readlink "$filename")
    if [[ "$target" == /* ]]; then filename=$target; else filename="${filename%/*}/$target"; fi
  done
  echo >&2 "ERROR: Cannot find application runfiles for $1"
  exit 1
}
find_interpreter() {
  case "$INTERPRETER_KIND" in
    runfiles) python_actual="$RUNFILES_DIR/$PYTHON_BINARY_ACTUAL" ;;
    absolute) python_actual="$PYTHON_BINARY_ACTUAL" ;;
    path) python_actual=$(command -v "$PYTHON_BINARY_ACTUAL") ;;
  esac
  if [[ "$python_actual" != /* ]]; then python_actual="$PWD/$python_actual"; fi
}

temporary_zip=""
working_directory=""
if [[ "$IS_ZIPFILE" == 0 ]]; then
  find_runfiles_root "$0"
  if [[ "$RUNFILES_DIR" != /* ]]; then RUNFILES_DIR="$PWD/$RUNFILES_DIR"; fi
  export RUNFILES_DIR
  find_interpreter
  if [[ "$RECREATE_VENV_AT_RUNTIME" == 1 ]]; then
    # No resource exists yet. The Python entry owns all subsequent preparation.
    exec "$python_actual" -I -S "$RUNFILES_DIR/$BOOTSTRAP_DRIVER" directory \
      "$RUNFILES_DIR" "$APPLICATION_SPEC" "$STAGE2_BOOTSTRAP" "$BOOTSTRAP_CLEANUP" \
      "${#additional_interpreter_args[@]}" "${additional_interpreter_args[@]}" "$@"
  fi
  python_exe=$python_actual
  if [[ -n "$PYTHON_BINARY" ]]; then python_exe="$RUNFILES_DIR/$PYTHON_BINARY"; fi
  entry="$RUNFILES_DIR/$STAGE2_BOOTSTRAP"
else
  if [[ "$INTERPRETER_KIND" != runfiles ]]; then
    find_interpreter
    # An external interpreter is available before any allocation.
    exec "$python_actual" -I -S -c \
      'import runpy,sys; runpy.run_path(sys.argv[1])["shell_main"](sys.argv[1],sys.argv[2:])' \
      "$0" "${#additional_interpreter_args[@]}" "${additional_interpreter_args[@]}" "$@"
  fi
  destination=""
  cached=0
  parent="${TMPDIR:-/tmp}"
  if [[ "$CACHE" == 1 && -n "${RULES_PYTHON_EXTRACT_ROOT:-}" ]]; then
    destination="$RULES_PYTHON_EXTRACT_ROOT/$CACHE_NAME/$APP_HASH"
    if [[ "$destination" != /* ]]; then destination="$PWD/$destination"; fi
    parent="${destination%/*}"
    mkdir -p "$parent"
    if [[ "$RESOLVE_PYTHON_BINARY_AT_RUNTIME" == 0 && ( -e "$destination" || -L "$destination" ) ]]; then
      if [[ ! -f "$destination/.rules_python_complete" ]]; then
        echo >&2 "ERROR: Incomplete Python runtime at $destination; use a clean extract root"
        exit 1
      fi
      cached=1
    fi
  fi
  if [[ "$cached" == 1 ]]; then
    # A completed bundled image already contains its final environment. No
    # temporary resource or preparer is needed to enter it.
    RUNFILES_DIR="$destination/runfiles"
    find_interpreter
    python_exe=$python_actual
    if [[ -n "$PYTHON_BINARY" ]]; then python_exe="$RUNFILES_DIR/$PYTHON_BINARY"; fi
    entry="$RUNFILES_DIR/$STAGE2_BOOTSTRAP"
    if [[ ! -f "$python_exe" || ! -x "$python_exe" || ! -f "$entry" || ! -r "$entry" ]]; then
      echo >&2 "ERROR: Invalid prepared Python application at $destination"
      exit 1
    fi
  else
    own_workspace "$parent"
    image="$workspace/image"
    status=0
    run_preparer unzip -q -d "$image" "$0" 2>/dev/null || status=$?
    if [[ "$status" -gt 1 ]]; then
      echo >&2 "ERROR: Unable to extract Python application (unzip status $status)"
      exit "$status"
    fi
    RUNFILES_DIR="$image/runfiles"
    export RUNFILES_DIR
    unset RUNFILES_MANIFEST_FILE
    find_interpreter
    run_preparer "$python_actual" -I -S "$RUNFILES_DIR/$BOOTSTRAP_DRIVER" \
      prepare-archive "$workspace" "$image" "$cached"
    declare -a result=()
    field=""
    while IFS= read -r -d '' field; do result+=("$field"); done < "$workspace/invocation"
    if [[ "${#result[@]}" != 6 || "${result[0]}" != 1 || -n "$field" ]]; then
      echo >&2 "ERROR: Invalid Python preparation result"
      exit 1
    fi
    working_directory=${result[1]}
    RUNFILES_DIR=${result[2]}
    python_exe=${result[3]}
    entry=${result[4]}
    temporary_zip=${result[5]}
    if [[ -n "$temporary_zip" && "$temporary_zip" != "$workspace" ]]; then
      echo >&2 "ERROR: Python preparation changed workspace ownership"
      exit 1
    fi
    if [[ -z "$temporary_zip" ]]; then
      rm -rf "$workspace"
      workspace=""
    fi
  fi
  unset RUNFILES_MANIFEST_FILE
fi

export RUNFILES_DIR
if [[ -z "${PYTHONSAFEPATH+x}" ]]; then export PYTHONSAFEPATH=1; fi
if [[ -n "${RULES_PYTHON_TESTING_TELL_RUNFILES_ROOT:-}" ]]; then
  export RULES_PYTHON_TESTING_RUNFILES_ROOT="$RUNFILES_DIR"
fi
declare -a options=()
if [[ -n "$temporary_zip" ]]; then options+=("-XRULES_PYTHON_ZIP_DIR=$temporary_zip/image"); fi
options+=("${additional_interpreter_args[@]}" "${INTERPRETER_ARGS_FROM_TARGET[@]}")
if [[ -n "$workspace" && -z "${RULES_PYTHON_BOOTSTRAP_VERBOSE:-}" ]]; then
  run_preparer "$python_exe" -I -S "$RUNFILES_DIR/$BOOTSTRAP_CLEANUP" "$$" "$workspace"
fi
if [[ "${RUN_UNDER_RUNFILES:-}" == 1 ]]; then working_directory="$RUNFILES_DIR/$WORKSPACE_NAME"; fi
if [[ -n "$working_directory" ]]; then cd "$working_directory"; fi
exec "$python_exe" "${options[@]}" "$entry" "$@"
# A self-executable archive can follow this prelude.
exit 1

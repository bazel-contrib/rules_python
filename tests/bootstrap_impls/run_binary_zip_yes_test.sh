# Copyright 2024 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# --- begin runfiles.bash initialization v3 ---
# Copy-pasted from the Bazel Bash runfiles library v3.
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  { echo>&2 "ERROR: cannot find $f"; exit 1; }; f=; set -e
# --- end runfiles.bash initialization v3 ---
set +e

bin=$(rlocation $BIN_RLOCATION)
if [[ -z "$bin" ]]; then
  echo "Unable to locate test binary: $BIN_RLOCATION"
  exit 1
fi
actual=$($bin)

# How we detect if a zip file was executed from depends on which bootstrap
# is used.
# bootstrap_impl=script outputs RULES_PYTHON_ZIP_DIR:<somepath>
# bootstrap_impl=system_python outputs file:.*Bazel.runfiles (or .exe.runfiles on Windows)
expected_pattern="RULES_PYTHON_ZIP_DIR:/\|file:.*Bazel.runfiles\|file:.*\.exe\.runfiles"
if ! (echo "$actual" | grep "$expected_pattern" ) >/dev/null; then
  echo "expected output to match: $expected_pattern"
  echo "but got: $actual"
  exit 1
fi

case "$(uname -s)" in
  CYGWIN*|MINGW*|MSYS*) exit 0 ;;
esac

test_dir=$(mktemp -d)
launcher_pid=""
application_pid=""
watchdog_pid=""

cleanup() {
  if [[ -n "${watchdog_pid}" ]]; then
    kill "${watchdog_pid}" 2>/dev/null || true
  fi
  if [[ -n "${launcher_pid}" ]]; then
    kill -KILL "${launcher_pid}" 2>/dev/null || true
  fi
  if [[ -n "${application_pid}" ]]; then
    kill -KILL "${application_pid}" 2>/dev/null || true
  fi
  rm -rf "${test_dir}"
}
trap cleanup EXIT

run_signal_case() {
  local mode="$1"
  local expected_exit="$2"
  local expected_output="$3"
  local log="${test_dir}/${mode}.log"

  "$bin" "${mode}" >"${log}" 2>&1 &
  launcher_pid=$!
  for _ in {1..100}; do
    if grep -F "ready:" "${log}" >/dev/null; then
      break
    fi
    sleep 0.1
  done
  grep -F "ready:" "${log}" >/dev/null || return 1
  application_pid=$(sed -n 's/^ready://p' "${log}")

  kill -TERM "${launcher_pid}"
  (
    sleep 10
    kill -KILL "${launcher_pid}" "${application_pid}" 2>/dev/null || true
  ) &
  watchdog_pid=$!
  wait "${launcher_pid}"
  exit_code=$?
  kill "${watchdog_pid}" 2>/dev/null || true
  watchdog_pid=""

  if [[ "${exit_code}" != "${expected_exit}" ]]; then
    echo "expected exit ${expected_exit}, got ${exit_code}" >&2
    cat "${log}" >&2
    return 1
  fi
  if [[ -n "${expected_output}" ]]; then
    grep -F "${expected_output}" "${log}" >/dev/null || return 1
  fi
  launcher_pid=""
  application_pid=""
}

run_signal_case handled 0 "received:15" || exit 1
run_signal_case unhandled 143 "" || exit 1

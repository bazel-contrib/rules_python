#!/bin/bash
set -euo pipefail

# rules_python_get_runfiles_path is a helper to correctly look up runfiles.
# It is needed because on Windows, the path to a runfile can be absolute,
# which is not something that bash can handle. So we use cygpath to fix it up.
rules_python_get_runfiles_path() {
    local path="$1"
    if [[ -f /bin/cygpath ]]; then
        cygpath -u "${path}"
    else
        echo "${path}"
    fi
}

source "$(rules_python_get_runfiles_path "$(dirname "$0")/verify.sh")"
verify_output "$(rules_python_get_runfiles_path "$(dirname "$0")/outer_calls_inner_script_python.out")"

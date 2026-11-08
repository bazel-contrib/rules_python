#!/usr/bin/env bash
set -euo pipefail

# Programmatically probe which repository target name is resolved successfully inside this workspace
if bazel query @pythons_hub//... >/dev/null 2>&1; then
  HUB_REPO="@pythons_hub"
elif bazel query @@rules_python++python+pythons_hub//... >/dev/null 2>&1; then
  HUB_REPO="@@rules_python++python+pythons_hub"
else
  HUB_REPO="@@+python+pythons_hub"
fi

# Query standard toolchains inside the resolved hub repository, excluding CC and Exec Tools toolchains.
bazel query "kind('toolchain', ${HUB_REPO}//...) - filter('_py_cc_toolchain$', ${HUB_REPO}//...) - filter('_py_exec_tools_toolchain$', ${HUB_REPO}//...)" "$@"

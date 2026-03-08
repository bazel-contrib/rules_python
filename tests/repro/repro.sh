#!/bin/bash

export USE_BAZEL_VERSION=8.x
export USE_BAZEL_VERSION=8.2.1
##export USE_BAZEL_VERSION=8.6.0
export USE_BAZEL_VERSION=9.x

##export PYTHONDONTWRITEBYTECODE=1
##export PYTHONPYCACHEPREFIX=/tmp/bazelpycache

##    --announce_rc \
##    --experimental_check_external_repository_files \
##    --experimental_check_external_other_files \
##    --experimental_repository_cache_hardlinks \
##    --watchfs \
function run_test() {
  bazel run \
    //tests/repro:bin
}
##set -x

echo "==== Invocation 1 ===="
echo "======================"
run_test

pydir=bazel-rules_python/external/+python+python_3_11_14_x86_64-unknown-linux-gnu

#touch $pydir/lib/python3.11/importlib
##rm -fr $pydir/lib/python3.11/importlib/__pycache__/*

echo "==== Invocation 2 ===="
echo "======================"
run_test

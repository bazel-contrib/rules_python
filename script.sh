#!/bin/bash

args=(
    uv
    pip
    compile
    "--generate-hashes"
    "--no-strip-extras"
)

"${args[@]}" \
    --directory examples/bzlmod \
    requirements.in \
    --python-version=3.9 \
    --output-file requirements_lock_3_9.txt \
    --universal \
    --custom-compile-command="bazel run //examples:bzlmod_requirements_3_9.update" \
    --emit-index-url

#!/usr/bin/env bash

set -eou pipefail

# Only forward environment variables that docs/conf.py actually reads so
# volatile per-container variables (like HOSTNAME or READTHEDOCS_OUTPUT) do not
# bust the SphinxBuildDocs action cache.
declare -a build_flags=(
  "--@sphinxdocs//sphinxdocs:extra_defines=version=${READTHEDOCS_VERSION:-0.0.0}"
  "--@sphinxdocs//sphinxdocs:extra_env=READTHEDOCS=${READTHEDOCS:-}"
)

if [[ "${READTHEDOCS_VERSION_TYPE:-}" != "external" ]]; then
  build_flags+=(
    "--@sphinxdocs//sphinxdocs:extra_env=READTHEDOCS_GIT_COMMIT_HASH=${READTHEDOCS_GIT_COMMIT_HASH:-}"
    "--@sphinxdocs//sphinxdocs:extra_env=READTHEDOCS_GIT_IDENTIFIER=${READTHEDOCS_GIT_IDENTIFIER:-}"
    "--@sphinxdocs//sphinxdocs:extra_env=READTHEDOCS_VERSION=${READTHEDOCS_VERSION:-}"
  )
fi

if [[ "${READTHEDOCS_VERSION_TYPE:-}" == "tag" || \
      "${READTHEDOCS_VERSION:-}" == "stable" ]]; then
  build_flags+=("--stamp")
fi

buildbuddy_config=""
buildbuddy_key=""
if [[ "${READTHEDOCS_VERSION_TYPE:-}" == "external" && \
      -n "${BUILDBUDDY_CAS_ONLY_KEY:-}" ]]; then
  buildbuddy_config="buildbuddy_presubmit"
  buildbuddy_key="${BUILDBUDDY_CAS_ONLY_KEY}"
elif [[ "${READTHEDOCS_VERSION_TYPE:-}" != "external" && \
        -n "${BUILDBUDDY_READ_WRITE_KEY:-}" ]]; then
  buildbuddy_config="buildbuddy_postsubmit"
  buildbuddy_key="${BUILDBUDDY_READ_WRITE_KEY}"
fi

if [[ -n "${buildbuddy_config}" && -n "${buildbuddy_key}" ]]; then
  printf 'common:%s --remote_header=x-buildbuddy-api-key=%s\n' \
    "${buildbuddy_config}" "${buildbuddy_key}" >> user.bazelrc
  build_flags+=(
    "--config=${buildbuddy_config}"
    "--build_metadata=ROLE=CI"
    "--build_metadata=VISIBILITY=PUBLIC"
  )
  if [[ -n "${READTHEDOCS_GIT_COMMIT_HASH:-}" ]]; then
    build_flags+=(
      "--build_metadata=COMMIT_SHA=${READTHEDOCS_GIT_COMMIT_HASH}"
    )
  fi
  if [[ "${READTHEDOCS_VERSION_TYPE:-}" == "external" && \
        -n "${READTHEDOCS_VERSION:-}" ]]; then
    build_flags+=("--build_metadata=PR_NUMBER=${READTHEDOCS_VERSION}")
  elif [[ -n "${READTHEDOCS_GIT_IDENTIFIER:-}" ]]; then
    # ${var//[^...]/} strips characters outside [a-zA-Z0-9._/-].
    safe_branch="${READTHEDOCS_GIT_IDENTIFIER//[^a-zA-Z0-9._\/-]/}"
    build_flags+=("--build_metadata=BRANCH_NAME=${safe_branch}")
  fi
fi

(
  set -x
  bazel run \
    --config=rtd \
    "${build_flags[@]}" \
    //docs:readthedocs_install
)

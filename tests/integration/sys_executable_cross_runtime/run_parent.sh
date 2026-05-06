#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

"${PARENT_BINARY}" "${MODE}"

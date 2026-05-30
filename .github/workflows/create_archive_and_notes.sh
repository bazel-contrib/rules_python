#!/usr/bin/env bash
# Copyright 2023 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o nounset
set -o pipefail
set -o errexit

set -x

TAG=$1
if [ -z "$TAG" ]; then
  echo "ERROR: TAG env var must be set"
  exit 1
fi
# If the workflow checks out one commit, but is releasing another
git fetch origin tag "$TAG"

# Update our local state so that check_version_markers searches what we expect
git checkout "$TAG"
$(dirname $0)/check_version_markers.sh

# A prefix is added to better match the GitHub generated archives.
PREFIX="rules_python-${TAG}"
ARCHIVE="rules_python-$TAG.tar.gz"
git archive --format=tar "--prefix=${PREFIX}/" "$TAG" | gzip > "$ARCHIVE"

cat > release_notes.txt << EOF

For more detailed setup instructions, see https://rules-python.readthedocs.io/en/latest/getting-started.html

For the user-facing changelog see [here](https://rules-python.readthedocs.io/en/latest/changelog.html#v${TAG//./-})

## Using

Add to your \`MODULE.bazel\` file:

\`\`\`starlark
bazel_dep(name = "rules_python", version = "${TAG}")

python = use_extension("@rules_python//python/extensions:python.bzl", "python")
python.toolchain(
    python_version = "3.13",
)

pip = use_extension("@rules_python//python/extensions:pip.bzl", "pip")
pip.parse(
    hub_name = "pypi",
    python_version = "3.13",
    requirements_lock = "//:requirements_lock.txt",
)

use_repo(pip, "pypi")
\`\`\`

For \`WORKSPACE\` users, please use rules_python through \`bzlmod\` by loading the rest of your
dependencies through the \`WORKSPACE.bzlmod\` file.

EOF

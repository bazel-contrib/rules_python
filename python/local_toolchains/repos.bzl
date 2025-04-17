"""Rules/macros for repository phase for local toolchains.

:::{versionadded} VERSION_NEXT_FEATURE
:::
"""

load(
    "@rules_python//python/private:local_runtime_repo.bzl",
    _local_runtime_repo = "local_runtime_repo",
)
load(
    "@rules_python//python/private:local_runtime_toolchains_repo.bzl",
    _local_runtime_toolchains_repo = "local_runtime_toolchains_repo",
)

local_runtime_repo = _local_runtime_repo

local_runtime_toolchains_repo = _local_runtime_toolchains_repo

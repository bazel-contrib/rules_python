"""Loads the workloads from `workloads.bzl` with the shim."""

import os

from tests.perf import starlark_shim


def workloads():
    """Return the dict of the workload names and the functions to measure."""
    shim = starlark_shim.Shim(_resolver())
    return shim.load("//tests/perf:workloads.bzl")["WORKLOADS"]


def _resolver():
    # When executed from the root of the repository without Bazel.
    if os.path.exists("python/private/version.bzl"):
        return lambda path: path

    from python.runfiles import runfiles

    rfiles = runfiles.Create()
    assert rfiles is not None, "Failed to create runfiles"

    def resolve(path):
        # The main repository is `_main` with bzlmod and `rules_python` without.
        for repo in ["_main", "rules_python"]:
            resolved = rfiles.Rlocation("{}/{}".format(repo, path))
            if resolved and os.path.exists(resolved):
                return resolved
        raise FileNotFoundError(path)

    return resolve

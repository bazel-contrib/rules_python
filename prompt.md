
We're adding uv.lock support to pip.parse.

A test has been added to `//test/uv_pypi`

Verify functionality by running `bazel run //tests/uv_pypi:bin`

The desired interface is by setting a `uv_lock` attribute in `pip.parse`. This
has been configured in MODULE.bazel for the test already:

```
dev_pip.parse(
    hub_name = "uv_pypi",
    python_version = "3.12",
    uv_lock = "//tests/uv_pypi:uv.lock",
)
```

A key helper to accomplish this is to use the toml2json tool, which handles
converting the toml-format of uv.lock to JSON, which can then be processed
by Starlark code. The name of this helper is `convert_uv_lock_to_json`
in `python/private/pypi/uv_lock.bzl`

Some background:

The pypi integration uses a "hub" and "spokes" design. The hub is the
`@uv_pypi` repo. This is basically a collection of BUILD files that
have aliases that point to spoke repos. Spoke repos use the `whl_library`
repository rule which downloads and extracts that actual wheel.

Part 1:

Analyze the pypi extension code base and write a plan of changes to make to
`plan.md` that accomplish the different parts of what needs to be done.

Part 2:

Modify the pip.parse extension to convert the uv.lock file to JSON.

From that, create a whl_library for each wheel URL. For now, if there
are multiple versions of a package, take the highest version package. If
there are multiple wheel URLs, use the first one.

Part 3:

Modify the whl_library generation logic to handle when there are multiple
versions of a package available. This should use the "resolution-markers"
information to generate select() expressions to pick between the different
packages available. The wheel_tags_settings rule is a key helper for this:
it can take a resolution-markers expression and evaluate it so that select()
expressions can match it.

As part of implementing this logic, the BUILD file for a package in the hub
repo should use wheel_tags_settings. For example, if the absl_py package
has two wheels, then the hub build file should look something like:

```
# File: @uv_pypi//absl_py:BUILD.bazel

define_wheel_tag_settings([
  ("@absl_py_a//:pkg", "resolution marker expr for a"),
  ("@absl_py_b//:pkg", "resolution marker expr for b"),
])
alias(
  name = "absl_py",
  actual = select({
    "pick_0": "@absl_py_a//:pkg",
    "pick_1": "@absl_py_b//:pkg",
  })
)
```

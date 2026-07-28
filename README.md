# Python Rules for Bazel

[![Build status](https://badge.buildkite.com/0bcfe58b6f5741aacb09b12485969ba7a1205955a45b53e854.svg?branch=main)](https://buildkite.com/bazel/rules-python-python)

## Overview

This repository is the home of the core Python rules -- `py_library`,
`py_binary`, `py_test`, and related symbols that provide the basis for Python
support in Bazel. It also contains package installation rules for integrating
with PyPI and other indices.

Documentation for rules_python is at <https://rules-python.readthedocs.io> and in the
[Bazel Build Encyclopedia](https://docs.bazel.build/versions/master/be/python.html).

Examples live in the [examples](examples) directory.

The core rules are stable. Their implementation is subject to Bazel's
[backward compatibility policy](https://docs.bazel.build/versions/master/backward-compatibility.html).
This repository aims to follow [semantic versioning](https://semver.org).

The Bazel community maintains this repository. Neither Google nor the Bazel team
provides support for the code. However, this repository is part of the test
suite used to vet new Bazel releases. See [How to contribute](CONTRIBUTING.md)
page for information on our development workflow.

## Design

* Supported OSes - as per our supported platform policy, we strive for support
  on all of the platforms that we have CI for. Some platforms do not have the
  same backwards compatibility guarantees, but we hope the community can step in
  where needed to make the support more robust.
* `requirements.txt` is how users have been defining dependencies for a long
  time. We support this to support legacy usecases or package managers that we
  don't support directly. Any additional information that we need will be
  retrieved from the SimpleAPI during the `bzlmod` extension evaluation phase.
  Then it will be written to the `MODULE.bazel.lock` file for future reuse. We
  have plans to support `uv.lock` file directly. `uv` is recommended for
  generating a fully locked `requirements.txt` file and we do provide a rule for
  it.
* The `py_binary`, `py_test` rules should scale to large monorepos and we work
  hard to minimize the work done during analysis and build phase. What is more,
  the space requirements for should be minimal, so we strive to use symlinks
  rather than extracting wheels at build time. This means that for different
  configurations of the same build, we are not extracting the wheel multiple
  times thus scaling better over the time. From `2.0` onwards we are creating a
  virtual env for each target by creating an actual minimal virtual environment
  using symlinks. We plan on creating the traditional `site-packages` layout in
  the future by default.
* Support for standards - we strive to first implement any standards needed
  within `rules_python` and this has resulted in a few PEPs supported within
  pure starlark - PEP440, PEP509.

Common misconceptions:
* `rules_python` has to keep backwards compatibility with `google3`. Whilst this
  might have been true in the past, `rules_python` is an open source project and
  any compatibility needs should come from the community - we have no
  requirement to keep this compatibility and are allowed to make our decisions.
  However, we do want to keep backwards compatibility as long as possible to not
  upset users with never ending migrations.
* `rules_python` is not caching pip downloads. With 2.0, we use Bazel's
  downloader by default and rely on bazel to provide the repository caching
  mechanisms. This means that for simpler setups this should result in
  transparent and scalable caching with the most recent bazel versions unless
  there are issues in the bazel itself.

## Documentation

For detailed documentation, see <https://rules-python.readthedocs.io>

## Bzlmod support

See [Bzlmod support](BZLMOD_SUPPORT.md) for more details.

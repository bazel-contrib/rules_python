:::{default-domain} bzl
:::

# Testing with pytest

{obj}`pytest_test` runs [pytest] tests with [pytest-bazel], a pytest runner
that follows the Bazel [test encyclopedia]. It writes its own `main` that
runs pytest on the `srcs`, so there is no `main` to maintain, and creates a
test per Python version with `python_versions`.

## Setup

`pytest_test` depends on `@pypi//pytest` and `@pypi//pytest_bazel` by
default. Add `pytest` and `pytest-bazel>=1.0` to the requirements that
{obj}`pip.parse` reads for the {ref}`unified @pypi hub <unified-pypi-hub>`,
or pass other targets with the `pytest` and `pytest_bazel` arguments.

```starlark
load("@rules_python//python:pytest_test.bzl", "pytest_test")

pytest_test(
    name = "lib_test",
    srcs = ["lib_test.py"],
    deps = [":lib"],
)

pytest_test(
    name = "lib_all_test",
    srcs = ["lib_test.py"],
    # A `lib_all_py3.13_test` and a `lib_all_py3.14_test` in a test suite
    # named `lib_all_test`.
    python_versions = ["3.13", "3.14"],
    deps = [":lib"],
)
```

`pytest-randomly` is optional. Pass `pytest_randomly = "@pypi//pytest_randomly"`
to run the tests in a random order, which `pytest-bazel` seeds from
`--runs_per_test`, so that each run uses a different order that can be
reproduced.

To use `pytest-bazel` with a plain {obj}`py_test`, call it from the `main`:

```python
import pytest_bazel

if __name__ == "__main__":
    pytest_bazel.main()
```

## What pytest-bazel does

The [pytest-bazel docs][pytest-bazel] show each feature with the output of
an example. The main ones are:

| Bazel | pytest-bazel | Docs |
| --- | --- | --- |
| `--test_filter` | Selects tests by their exact names, e.g. `TestClass.test_fn`, a path or a pytest node id, or several of them separated by commas. A filter with spaces is a `-k` expression. | [Test filter][test-filter] |
| `shard_count` | Splits the tests into balanced shards, no `pytest-shard` needed. | [Sharding][sharding] |
| `--runs_per_test`, `--test_env=TEST_RANDOM_SEED=...` | Seeds `pytest-randomly`, or `random.seed` without it. | [Runs per test][runs-per-test] |
| `--test_runner_fail_fast` | Stops at the first failure. | [Fail fast][fail-fast] |
| Test timeouts | Prints the stacks of all threads, and of the `pytest-xdist` workers, when Bazel stops the test. | [Timeout][timeout], [xdist][xdist] |
| `bazel-testlogs` | Writes the JUnit XML with the output of failed tests, keeps the `tmp_path` of failed tests in `test.outputs` and writes the warnings to `test.warnings`. | [JUnit XML][junit-xml], [Keep failed tmp_path][keep-failed-tmp-path], [Warnings][warnings] |
| `TEST_TMPDIR` | Points `TMPDIR` and pytest's `tmp_path` at it, so tests do not write outside the sandbox. | [Temporary directories][tmpdir] |
| `bazel run` | Debug a test with `bazel run //pkg:test -- --pdb`, as `bazel test` gives tests no terminal. | [Debugging][debugging] |

Paths in tracebacks and warnings are relative to the workspace root, so
editors can open them, see [Editors][editors].

## Configuration

pytest reads its config file, e.g. `pytest.ini` or `pyproject.toml`, from the
runfiles: add it to the `data` of the test. `pytest-bazel` also uses the
config file in the Bazel package of the test or in its parents, see
[Config from package][config-from-package].

Pass pytest flags with `args` or `--test_arg`, e.g.
`bazel test //pkg:test --test_arg=-vv`.

The behaviours of `pytest-bazel` that changed in 1.0 can be turned off with
an env var set to `0`, in the `env` of a test or for all tests with
`--test_env`:

```starlark
pytest_test(
    name = "lib_test",
    srcs = ["lib_test.py"],
    env = {"PYTEST_BAZEL_EXACT_TEST_FILTER": "0"},
)
```

See the [flags][flags] for the list.

[pytest]: https://docs.pytest.org/
[pytest-bazel]: https://pytest-bazel.readthedocs.io/latest/
[test encyclopedia]: https://bazel.build/reference/test-encyclopedia
[test-filter]: https://pytest-bazel.readthedocs.io/latest/features/test-filter.html
[sharding]: https://pytest-bazel.readthedocs.io/latest/features/sharding.html
[runs-per-test]: https://pytest-bazel.readthedocs.io/latest/features/runs-per-test.html
[fail-fast]: https://pytest-bazel.readthedocs.io/latest/features/fail-fast.html
[timeout]: https://pytest-bazel.readthedocs.io/latest/features/timeout.html
[xdist]: https://pytest-bazel.readthedocs.io/latest/features/xdist.html
[junit-xml]: https://pytest-bazel.readthedocs.io/latest/features/junit-xml.html
[keep-failed-tmp-path]: https://pytest-bazel.readthedocs.io/latest/features/keep-failed-tmp-path.html
[warnings]: https://pytest-bazel.readthedocs.io/latest/features/warnings.html
[tmpdir]: https://pytest-bazel.readthedocs.io/latest/features/tmpdir.html
[debugging]: https://pytest-bazel.readthedocs.io/latest/features/debugging.html
[editors]: https://pytest-bazel.readthedocs.io/latest/editors.html
[config-from-package]: https://pytest-bazel.readthedocs.io/latest/features/config-from-package.html
[flags]: https://github.com/aignas/pytest-bazel#flags

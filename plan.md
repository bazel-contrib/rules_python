For all of the steps do small changes and ensure that each commit is compliant with:
* buildifier and buildifier-lint pre-commit hooks
* isort and black pre-commit hooks
* all of the bazel tests pass
* Spin a sub-agent with a different model and monitor code quality to ensure it is high.
* Ensure that comments are minimal and not too verbose.
* Once done with each section, squash the commit and have a description that is good for a PR.

Already done:
* Then implement support for `uv.lock` as follows:
    1. Add support to generate `uv.lock` from the `lock` rule in rules_python.
    2. Add unit/integration tests for this feature.
    3. Ensure that both actions to update the lock file work.
    4. Use the docs/pyproject.toml for integration testing.
    5. Support updating requirements and the uv.lock file together.

* Look at the architecture in one of the last comments on https://github.com/bazel-contrib/rules_python/issues/2787.
    1. Take the uv.lock to json converter from a PR that is associated with the linked issue
    2. Include the integration and unit tests for the converter.

In progress bellow:

Then add the uv.lock support to pip.parse by accepting the lock file.
1. parse_requirements should accept an extra parameter called uv lock.
2. If both requirements and uv.lock is passed and we are running from inside rules_python, run in a
   debug mode where we test that uv.lock and requirements are consistent. Ensure that we pick used
   extras from the uv.lock file. If uv.lock is provided, use only the uv.lock file for inputs and
   use requirements files as a test mechanism - ensure that parsing uv.lock and using it to return
   the output of parse_requirements function results in the same as what we would have returned with
   just using the requirements files.
3. Use uv.lock packages, extras and the file shas to get the equivalent information to what is in
   requirements.txt.
4. Iterate until the packages read from uv.lock file are the same as the ones that we retrieve from
   the requirements files.
5. Along the way add integration tests and keep running full `//tests/pypi/...` suite between the
   changes.
6. Run `bazel build //docs:sphinx-build` as an extra verification.
7. Use `fail` if the invariants are broken.

Then look online on the uv-lock file repository and add test cases to ensure that we are correctly
handling in requirements and lock files the following cases:
1. Overrides of whl files where we need to fetch the wheel from a particular location/index
2. All of the cases where requirements files use direct URL references or VCS references.

Then implement a Starlark uv.lock file parser that would be good enough for parsing any file in the
test suite of uv.lock file. Use the `python` version that we have introduced earlier for the
expected result.
1. Base the parser on https://github.com/jvolkman/toml.bzl
2. Copy the all of the sample uv.lock files from the upstream `astral-sh/uv` test-suite.
3. Ensure that we are passing test-suite in there.

Then implement a wrapper around the `get_index` function to get the wheel sources from the uv.lock
file instead of calling the SimpleAPI.
1. If there are no URLs in the uv.lock file, fallback to the SimpleAPI code.

For all of this work, the output signature of the parse_requirements should stay the same.

## PR Review Cycle Instructions (for AI agents)

When addressing PR review comments:
1. Read all review comments (inline and summary) using `gh api` and `gh pr view`
2. Address each issue with appropriate code fixes
3. Add tests matching existing coverage patterns
4. Run all tests (`bazel test --config=fast-tests //tests/...`), build docs (`bazel build //docs:sphinx-build`)
5. Commit, push, request gemini review
6. Check Buildkite CI results (except RBE failures); fix any failures
7. Cycle until all green

## Done
1. First review cycle:
   - tomllib: try/except fallback to tomli for Python <3.11
   - json_serializer: add datetime.date and datetime.time support
   - all_platforms: use sorted(platforms.keys()) fallback
   - $PWD/ path: check if python_path is absolute
   - provides-extras: comment explaining inclusion rationale
   - extra_pip_args: pass through to _parse_uv_lock_json
   - Added uv_lock test coverage: multiple packages, extra_pip_args, multi-os
2. Python 3.14 toolchain in MODULE.bazel for toml.bzl usage
3. Integration test in tests/integration/uv_lock/
4. Dead code removed (uv_pypi test data), tomli fallback restored
5. toml2json removed in favor of pure Starlark toml.bzl decoder
6. uv_lock.bzl and toml2json tool deleted

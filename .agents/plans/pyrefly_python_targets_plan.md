# Plan: Pyrefly Python Targets Enablement & Review Resolutions

This plan documents findings, requirements, and issues discovered during the
review of Pyrefly static type checking enablement across `rules_python` and
`sphinxdocs` targets.

---

## 1. Review Findings & Answers

### 1.1 `dependency_resolver.py` Unbound Variable Scoping
- **File**: [`python/private/pypi/dependency_resolver/dependency_resolver.py`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/python/private/pypi/dependency_resolver/dependency_resolver.py#L137-L175)
- **User Directive**: Simplify by initializing `requirements_out =
  requirements_file_relative` up front before `if "TEST_TMPDIR" in os.environ:`.
- **Finding**: In the original code, `requirements_out` was conditionally
  assigned only inside `if "TEST_TMPDIR" in os.environ:`, causing Pyrefly to
  flag it as potentially unbound on subsequent references.
- **Requirement / Resolution**: Initialized `requirements_out =
  requirements_file_relative` before the test check, reassigning to scratch file
  only when under `TEST_TMPDIR`.

---

### 1.2 `sphinxdocs/MODULE.bazel` Hub Name
- **File**: [`sphinxdocs/MODULE.bazel`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/sphinxdocs/MODULE.bazel#L13-L25)
- **User Directive**: *"restore original name"*
- **Finding**: Restored `hub_name = "dev_pip"` with `use_repo(dev_pip,
  "dev_pip", "pypi")` and `dev_dependency = True` on `dev_pip = use_extension`.
- **Requirement / Resolution**: Restored `hub_name = "dev_pip"` and ensured
  `dev_dependency = True` is set on the extension usage.

---

### 1.3 `proto_to_markdown.py` Pyrefly Enablement
- **Files**:
  - [`sphinxdocs/sphinxdocs/private/BUILD.bazel`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/sphinxdocs/sphinxdocs/private/BUILD.bazel#L124-L148)
  - [`sphinxdocs/sphinxdocs/private/proto_to_markdown.py`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/sphinxdocs/sphinxdocs/private/proto_to_markdown.py#L21)
  - [`sphinxdocs/tests/proto_to_markdown/BUILD.bazel`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/sphinxdocs/tests/proto_to_markdown/BUILD.bazel#L17-L25)
  - [`sphinxdocs/tests/proto_to_markdown/proto_to_markdown_test.py`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/sphinxdocs/tests/proto_to_markdown/proto_to_markdown_test.py#L18-L20)
- **User Directive**: *"enable pyrefly, add disable comments where appropriate"*
- **Finding**: Pyrefly reported `missing-import` and `missing-source-for-stubs`
  on generated Protobuf Python stubs (`stardoc.proto.stardoc_output_pb2` and
  `google.protobuf.text_format`) because generated `.py` files from
  `py_proto_library` live in Bazel genfiles rather than source directories.
- **Requirement / Resolution**:
  1. Removed `tags = ["no-pyrefly"]` from `proto_to_markdown`,
     `proto_to_markdown_lib`, and `proto_to_markdown_test`.
  2. Added `# type: ignore` annotations to `stardoc_output_pb2` and
     `google.protobuf` imports in `proto_to_markdown.py` and
     `proto_to_markdown_test.py`.
  3. Verified type-checking and tests pass cleanly under `--config=fast-tests`.

---

### 1.4 `sphinx_build.py` Redundant Comments
- **File**: [`sphinxdocs/sphinxdocs/private/sphinx_build.py`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/sphinxdocs/sphinxdocs/private/sphinx_build.py#L22-L28)
- **User Directive**: *"the doc string captures this comment; remove redundant
  comment"*
- **Finding & Resolution**: Deleted redundant top-level comments above
  `WorkRequestInput` since the docstrings already contain the reference link.

---

### 1.5 `bzl.py` Overrides, Domain Helper, and Parameter Renaming
- **File**: [`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py#L605-L875)
- **User Directives & Questions**:
  1. *"requirement: keep all @override"*
  2. *"why was sig_text renamed? is it to match the overriden interface?"*
  3. *"why were these renamed? was it to match the interface?"*
  4. *"create a self._get_bzl_domain() helper so this logic doens't have to be
     duplicated everywhere"*
- **Finding & Resolution**:
  1. Created `_get_bzl_domain(self) -> _BzlDomain` helper method on
     `_BzlObject` and unified domain lookup across `add_target_and_index` and
     `_get_object_type_display_name`.
  2. Maintained `sig` and `name`/`signode` parameter names to match base
     `ObjectDescription` interfaces in Sphinx.
  3. Preserved all `@override` decorators on all overridden methods across
     `_BzlObject`, `_BzlCallable`, and `_BzlDomain`.

---

## 2. Target Status

| Target / Module | Status | Notes |
|---|---|---|
| `//sphinxdocs/private:proto_to_markdown` | Resolved | Pyrefly enabled with import ignores |
| `//sphinxdocs/private:proto_to_markdown_lib` | Resolved | Pyrefly enabled with import ignores |
| `//tests/proto_to_markdown:proto_to_markdown_test` | Resolved | Pyrefly enabled, 100% tests passing |
| `//sphinxdocs/private:sphinx_build_lib` | Resolved | Redundant comments removed, TypedDicts typed |
| `//sphinxdocs/src/sphinx_bzl:sphinx_bzl` | Resolved | `_get_bzl_domain()` helper added, overrides kept |
| `//python/private/pypi/dependency_resolver` | Resolved | `requirements_out` initialized cleanly up front |
| `sphinxdocs/MODULE.bazel` | Resolved | `hub_name = "dev_pip"` restored with `dev_dependency = True` |

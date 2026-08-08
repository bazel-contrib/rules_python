# Plan: Pyrefly Python Targets Enablement & Review Resolutions

This plan documents findings, requirements, and issues discovered during the
review of Pyrefly static type checking enablement across `rules_python` and
`sphinxdocs` targets, including detailed explanations for targets where
`no-pyrefly` is intentionally retained.

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

## 2. Targets with `no-pyrefly` Tag and Explanations

The following targets retain `tags = ["no-pyrefly"]` due to runtime-injected
modules, compiled native extensions without type stubs, or dynamically
generated test bootstrap wrappers:

### 2.1 `//tests/bootstrap_impls:bazel_tools_importable_system_python_test`
- **Location**: [`tests/bootstrap_impls/BUILD.bazel:108-119`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/bootstrap_impls/BUILD.bazel#L108-L119)
- **Source**: [`tests/bootstrap_impls/bazel_tools_importable_test.py`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/bootstrap_impls/bazel_tools_importable_test.py)
- **Explanation**: This test verifies legacy `system_python` bootstrapping
  behaviour and imports `@bazel_tools//tools/python/runfiles` with
  `legacy_create_init = True`. The `@bazel_tools` built-in repository does not
  provide `__init__.py` files or static type stubs, causing Pyrefly import
  resolution failures.

### 2.2 `//tests/build_data:build_data_test`
- **Location**: [`tests/build_data/BUILD.bazel:4-13`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/build_data/BUILD.bazel#L4-L13)
- **Source**: [`tests/build_data/build_data_test.py`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/build_data/build_data_test.py)
- **Explanation**: Tests the workspace build data stamping mechanism and
  imports `bazel_binary_info`. `bazel_binary_info` is an internal synthetic
  module generated dynamically at build time by the rule action template, so it
  does not exist as a static Python source file in the repository tree.

### 2.3 `//tests/build_data:print_build_data`
- **Location**: [`tests/build_data/BUILD.bazel:15-20`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/build_data/BUILD.bazel#L15-L20)
- **Source**: [`tests/build_data/print_build_data.py`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/build_data/print_build_data.py)
- **Explanation**: Helper binary executed during a `genrule` to emit stamped
  build data. Like `build_data_test`, it directly imports the dynamically
  injected `bazel_binary_info` synthetic module.

### 2.4 `//tests/cc/py_extension:py_extension_test`
- **Location**: [`tests/cc/py_extension/BUILD.bazel:171-180`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/cc/py_extension/BUILD.bazel#L171-L180)
- **Source**: [`tests/cc/py_extension/py_extension_test.py`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/cc/py_extension/py_extension_test.py)
- **Explanation**: Tests dynamic C extension (`py_extension`) shared library
  linking and symbol resolution. It imports `:ext_shared` (`ext_shared.so`),
  which is compiled from C sources and has no accompanying `.pyi` type stubs.

### 2.5 `//tests/cc/py_extension:py_extension_pkg_test`
- **Location**: [`tests/cc/py_extension/BUILD.bazel:189-196`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/cc/py_extension/BUILD.bazel#L189-L196)
- **Source**: [`tests/cc/py_extension/py_extension_pkg_test.py`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/cc/py_extension/py_extension_pkg_test.py)
- **Explanation**: Tests package-scoped C extension imports using
  `tests.cc.py_extension.ext_pkg_test`. The extension is a native compiled C
  module without static type stubs.

### 2.6 `//tests/pytest_test:pytest_script_venv_test`
- **Location**: [`tests/pytest_test/BUILD.bazel:4-15`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/pytest_test/BUILD.bazel#L4-L15)
- **Source**: [`tests/pytest_test/basic_test.py`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/pytest_test/basic_test.py)
- **Explanation**: Instantiated via the `pytest_test` macro, which generates an
  intermediate test runner bootstrap script (`pytest_script_venv_test_boot.py`)
  via `ctx.actions.expand_template`. Because the generated main entry point
  is created during analysis/execution, Pyrefly cannot inspect the main file
  statically from source.

### 2.7 `//tests/pytest_test:pytest_default_test`
- **Location**: [`tests/pytest_test/BUILD.bazel:17-24`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/pytest_test/BUILD.bazel#L17-L24)
- **Source**: [`tests/pytest_test/basic_test.py`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/pytest_test/basic_test.py)
- **Explanation**: Like `pytest_script_venv_test`, relies on the `pytest_test`
  macro with an action-generated bootstrap entry script
  (`pytest_default_test_boot.py`).

### 2.8 `//tests/venv_site_packages_libs:shared_lib_loading_test`
- **Location**: [`tests/venv_site_packages_libs/BUILD.bazel:53-73`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/venv_site_packages_libs/BUILD.bazel#L53-L73)
- **Source**: [`tests/venv_site_packages_libs/shared_lib_loading_test.py`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/venv_site_packages_libs/shared_lib_loading_test.py)
- **Explanation**: Tests virtual environment runtime shared library discovery
  and imports `:ext_with_libs` (a compiled C extension) alongside platform-
  conditional binary analysis libraries (`elftools` / `macholib`). The native C
  extension lacks static `.pyi` stubs.

---

## 3. Target Status Overview

| Target / Module | Status | Notes |
|---|---|---|
| `//sphinxdocs/private:proto_to_markdown` | Resolved | Pyrefly enabled with import ignores |
| `//sphinxdocs/private:proto_to_markdown_lib` | Resolved | Pyrefly enabled with import ignores |
| `//tests/proto_to_markdown:proto_to_markdown_test` | Resolved | Pyrefly enabled, 100% tests passing |
| `//sphinxdocs/private:sphinx_build_lib` | Resolved | Redundant comments removed, TypedDicts typed |
| `//sphinxdocs/src/sphinx_bzl:sphinx_bzl` | Resolved | `_get_bzl_domain()` helper added, overrides kept |
| `//python/private/pypi/dependency_resolver` | Resolved | `requirements_out` initialized cleanly up front |
| `sphinxdocs/MODULE.bazel` | Resolved | `hub_name = "dev_pip"` restored with `dev_dependency = True` |
| `//tests/bootstrap_impls:bazel_tools_importable_system_python_test` | `no-pyrefly` | `@bazel_tools` lacks init/stubs |
| `//tests/build_data:build_data_test` | `no-pyrefly` | Synthetic `bazel_binary_info` module |
| `//tests/build_data:print_build_data` | `no-pyrefly` | Synthetic `bazel_binary_info` module |
| `//tests/cc/py_extension:py_extension_test` | `no-pyrefly` | Compiled C extension without `.pyi` |
| `//tests/cc/py_extension:py_extension_pkg_test` | `no-pyrefly` | Compiled C extension without `.pyi` |
| `//tests/pytest_test:pytest_script_venv_test` | `no-pyrefly` | Action-generated bootstrap runner |
| `//tests/pytest_test:pytest_default_test` | `no-pyrefly` | Action-generated bootstrap runner |
| `//tests/venv_site_packages_libs:shared_lib_loading_test` | `no-pyrefly` | Compiled C extension without `.pyi` |

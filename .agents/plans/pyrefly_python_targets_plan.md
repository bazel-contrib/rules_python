# Plan: Pyrefly Python Targets Enablement & Review Resolutions

This plan documents findings, requirements, and resolutions discovered during the
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

## 2. Pyrefly Enablement & Suppression Explanations

Following review feedback, targets were updated to prefer `# type: ignore` on
specific un-typed imports and calls rather than disabling Pyrefly across entire
targets. Only targets generating runner wrappers at action execution time
retain `tags = ["no-pyrefly"]`.

### 2.1 Converted Targets (Pyrefly Enabled with `# type: ignore`)

1. **[`//tests/bootstrap_impls:bazel_tools_importable_system_python_test`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/bootstrap_impls/BUILD.bazel#L108-L119)**:
   - *Source*: [`tests/bootstrap_impls/bazel_tools_importable_test.py`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/bootstrap_impls/bazel_tools_importable_test.py#L7-L11)
   - *Resolution*: Removed `no-pyrefly` tag; added `# type: ignore` to
     `bazel_tools` and `@bazel_tools//tools/python/runfiles` imports.

2. **[`//tests/build_data:build_data_test`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/build_data/BUILD.bazel#L4-L13)** & **[`//tests/build_data:print_build_data`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/build_data/BUILD.bazel#L15-L20)**:
   - *Sources*: [`tests/build_data/build_data_test.py`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/build_data/build_data_test.py#L8) and [`tests/build_data/print_build_data.py`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/build_data/print_build_data.py#L1)
   - *Resolution*: Removed `no-pyrefly` tags; added `# type: ignore` on
     dynamically injected `bazel_binary_info` module imports and `None`-asserts
     on runfiles resolution.

3. **[`//tests/cc/py_extension:py_extension_test`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/cc/py_extension/BUILD.bazel#L171-L180)** & **[`//tests/cc/py_extension:py_extension_pkg_test`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/cc/py_extension/BUILD.bazel#L189-L196)**:
   - *Sources*: [`tests/cc/py_extension/py_extension_test.py`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/cc/py_extension/py_extension_test.py#L5) and [`tests/cc/py_extension/py_extension_pkg_test.py`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/cc/py_extension/py_extension_pkg_test.py#L3)
   - *Resolution*: Removed `no-pyrefly` tags; added `# type: ignore` to
     compiled C extension (`ext_shared`, `ext_pkg_test`) imports and dynamic ELF
     tag lookups.

4. **[`//tests/venv_site_packages_libs:shared_lib_loading_test`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/venv_site_packages_libs/BUILD.bazel#L53-L73)**:
   - *Source*: [`tests/venv_site_packages_libs/shared_lib_loading_test.py`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/venv_site_packages_libs/shared_lib_loading_test.py#L9-L40)
   - *Resolution*: Removed `no-pyrefly` tag; added `# type: ignore` to
     `ext_with_libs.adder`, `macholib`, `elftools`, and guarded platform-
     conditional imports.

### 2.2 Retained `no-pyrefly` Targets

1. **[`//tests/pytest_test:pytest_script_venv_test`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/pytest_test/BUILD.bazel#L4-L17)** & **[`//tests/pytest_test:pytest_default_test`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/tests/pytest_test/BUILD.bazel#L19-L28)**:
   - *Explanation*: Instantiated via the `pytest_test` macro, which generates
     an intermediate test runner bootstrap script (`*_boot.py`) at analysis /
     execution time via `ctx.actions.expand_template`. Because the generated main
     entry point does not exist in source, Pyrefly cannot inspect the file
     statically. Explanatory comments are documented above `tags = ["no-pyrefly"]`.

---

## 3. Target Status Overview

| Target / Module | Status | Notes |
|---|---|---|
| `//sphinxdocs/private:proto_to_markdown` | Resolved | Pyrefly enabled with `# type: ignore` |
| `//sphinxdocs/private:proto_to_markdown_lib` | Resolved | Pyrefly enabled with `# type: ignore` |
| `//tests/proto_to_markdown:proto_to_markdown_test` | Resolved | Pyrefly enabled, 100% tests passing |
| `//sphinxdocs/private:sphinx_build_lib` | Resolved | Redundant comments removed, TypedDicts typed |
| `//sphinxdocs/src/sphinx_bzl:sphinx_bzl` | Resolved | `_get_bzl_domain()` helper added, overrides kept |
| `//python/private/pypi/dependency_resolver` | Resolved | `requirements_out` initialized cleanly up front |
| `sphinxdocs/MODULE.bazel` | Resolved | `hub_name = "dev_pip"` restored with `dev_dependency = True` |
| `//tests/bootstrap_impls:bazel_tools_importable_system_python_test` | Resolved | Pyrefly enabled with `# type: ignore` |
| `//tests/build_data:build_data_test` | Resolved | Pyrefly enabled with `# type: ignore` |
| `//tests/build_data:print_build_data` | Resolved | Pyrefly enabled with `# type: ignore` |
| `//tests/cc/py_extension:py_extension_test` | Resolved | Pyrefly enabled with `# type: ignore` |
| `//tests/cc/py_extension:py_extension_pkg_test` | Resolved | Pyrefly enabled with `# type: ignore` |
| `//tests/venv_site_packages_libs:shared_lib_loading_test` | Resolved | Pyrefly enabled with `# type: ignore` |
| `//tests/pytest_test:pytest_script_venv_test` | `no-pyrefly` | Template-generated bootstrap runner |
| `//tests/pytest_test:pytest_default_test` | `no-pyrefly` | Template-generated bootstrap runner |

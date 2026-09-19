# Implementation Plan - Support Custom Metadata & PEP 639 in `py_wheel`

This plan details the design for issue
[#4042](https://github.com/bazel-contrib/rules_python/issues/4042) and generalized
distribution files:
1. `metadata_fields`: `attr.string_list_dict` (configurable, emitting one header
   line per list item).
2. `metadata_file`: `attr.label(allow_single_file = True)` (RFC 822 metadata file
   to merge into and take precedence over generated metadata).
3. `extra_distinfo_files`: `attr.label_keyed_string_dict` (enhanced with
   `strip_prefix|prefix` path transformation, `.dist-info` auto-stripping, and
   multi-file directory placement).
4. `license_expression`: `attr.string()` for {pep}`639`.

---

## Multiple-Value Header Formatting

In Core Metadata ({pep}`566` / RFC 822), multiple-use fields are represented as
repeated header lines with the same key.

In `metadata_fields`, each item in a key's list is emitted as a distinct header
line:

```python
metadata_fields = {
    "License-Expression": ["Apache-2.0 AND MIT"],
    "License-File": ["LICENSE", "third_party/dep.txt"],
    "Classifier": [
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
    ],
    "Dynamic": ["classifiers"],
}
```

Produces in `METADATA`:
```http
License-Expression: Apache-2.0 AND MIT
License-File: LICENSE
License-File: third_party/dep.txt
Classifier: License :: OSI Approved :: Apache Software License
Classifier: Programming Language :: Python :: 3
Dynamic: classifiers
```

---

## `extra_distinfo_files` Path Transformation Syntax

`extra_distinfo_files` maps labels to destination paths inside `.dist-info/`.

### 1. `strip_prefix|prefix` Syntax
To give users precise control over file paths inside `.dist-info/`, the value
supports a `strip_prefix|prefix` syntax:
- `strip_prefix` is removed from the beginning of each file's path.
- `prefix` is prepended to the remaining path under `.dist-info/`.

Example:
```python
extra_distinfo_files = {
    # Takes files from //some:licenses, removes "some/" prefix, and puts them
    # in the "licenses" directory under .dist-info/ (e.g. some/pkg/LICENSE ->
    # .dist-info/licenses/pkg/LICENSE)
    "//some:licenses": "some/|licenses",
}
```

#### Special Case: Empty `strip_prefix`
If `strip_prefix` is empty (e.g. `"|licenses"` or `"|"`), `{distribution-name}*.dist-info`
is searched for in the file's path. If found, the entire path segment up to and
including `.dist-info/` is automatically computed and used as the strip prefix:
- E.g. A file path `"foo/bar/mydist.dist-info/licenses/data.txt"` with `"|"` will
  have `"foo/bar/mydist.dist-info/"` stripped, placing `"licenses/data.txt"`
  under `.dist-info/licenses/data.txt`.

### 2. Standard Value Syntax (without `|`)
If `|` is not present in the value:
- **Single-file target**: If the target provides exactly 1 file, the value is
  the exact relative destination file path under `.dist-info/` (e.g.
  `"//:LICENSE": "licenses/LICENSE"`).
- **Multi-file target**: If the target provides multiple files, the value is
  treated as a directory under `.dist-info/`, placing each file using its
  basename (e.g. `":all_licenses": "licenses"` puts files under
  `.dist-info/licenses/<basename>`).

---

## Proposed Changes

### Packaging API & Rule Implementation

---

#### [MODIFY] [`python/packaging.bzl`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/add_py_wheel_metadata/python/packaging.bzl)

- Update `py_wheel` macro signature and docstrings to accept `metadata_fields`,
  `metadata_file`, `license_expression`.
- Forward all attributes to `_py_wheel`.

---

#### [MODIFY] [`python/private/py_wheel.bzl`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/add_py_wheel_metadata/python/private/py_wheel.bzl)

1. Add attributes to `py_wheel_lib.attrs`:
   - `metadata_fields`: `attr.string_list_dict()`
   - `metadata_file`: `attr.label(allow_single_file = True)`
   - `license_expression`: `attr.string()`
2. In `_py_wheel_impl`:
   - Support `strip_prefix|prefix` syntax (including auto-stripping
     `{dist}*.dist-info/` when `strip_prefix` is empty) and multi-file directory
     placement in `extra_distinfo_files`.
   - Enforce `license` vs `license_expression` mutual exclusion.
   - Format `metadata_fields` into repeated header lines.
   - Elevate `Metadata-Version` to `2.4` if `license_expression` or
     `License-Expression`/`License-File` is present in `metadata_fields`.
   - Pass `--merge_metadata_file` to `wheelmaker.py` when `metadata_file` is
     provided.

---

#### [MODIFY] [`tools/wheelmaker.py`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/add_py_wheel_metadata/tools/wheelmaker.py)

1. Add `--merge_metadata_file` CLI argument.
2. Support `extra_distinfo_file` destinations with full relative path handling
   and directory prefix resolution.
3. If `--merge_metadata_file` is provided, parse and merge RFC 822 headers and
   body into `METADATA` (taking precedence over generated base headers for
   single-use fields and appending for multi-use fields).

---

### Tests

---

#### [MODIFY] [`tests/py_wheel/py_wheel_tests.bzl`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/add_py_wheel_metadata/tests/py_wheel/py_wheel_tests.bzl)

- Analysis tests for:
  - `extra_distinfo_files` with `strip_prefix|prefix` syntax (including empty
    `strip_prefix` auto-stripping) and multi-file targets.
  - Multi-line header generation from `metadata_fields`.
  - `license_expression` mutual exclusion and `Metadata-Version: 2.4` elevation.
  - `metadata_file` action input and `--merge_metadata_file` argument
    propagation.

---

#### [MODIFY] [`examples/wheel/BUILD.bazel`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/add_py_wheel_metadata/examples/wheel/BUILD.bazel) and [`examples/wheel/wheel_test.py`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/add_py_wheel_metadata/examples/wheel/wheel_test.py)

- Integration tests verifying wheels containing:
  - `extra_distinfo_files` with `strip_prefix|prefix` and auto-stripped
    dist-info directories (licenses, SBOMs).
  - Multiple `License-File` and `Classifier` lines via `metadata_fields`.
  - Merged metadata from `metadata_file` taking precedence over base metadata.

---

## Verification Plan

### Automated Tests
1. Run analysis tests:
   ```bash
   bazel test --config=fast-tests //tests/py_wheel:...
   ```
2. Run wheel integration tests:
   ```bash
   bazel test --config=fast-tests //examples/wheel:wheel_test
   ```
3. Run all fast tests across the repository:
   ```bash
   bazel test --config=fast-tests //...
   ```
4. Verify documentation build:
   ```bash
   bazel build //docs:docs
   ```

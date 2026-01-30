# Wheel Permissions Test

This test verifies that `rules_python` can correctly handle Python wheels that contain files without read permissions.

## Background

Some wheels are created with files that have incorrect permissions (e.g., mode `000`). When these wheels are extracted by Bazel's `rctx.extract()`, the file permissions are preserved from the zip file. This causes failures when subsequent operations try to read these files, such as:

- Reading `__init__.py` files during namespace package detection
- Reading metadata files
- Importing Python modules

## Test Setup

### Files

- **`bad_perms_pkg-1.0-py3-none-any.whl`**: A pre-built test wheel with files that have mode `000` (no permissions)
- **`build_test_wheel.py`**: Script used to generate the test wheel (for reference/regeneration)
- **`whl_permissions_test.py`**: Integration test that verifies the wheel can be extracted and used

## Regenerating the Test Wheel

If you need to regenerate the test wheel:

```bash
bazel run //tests/pypi/whl_permissions:build_test_wheel -- \
  $(pwd)/tests/pypi/whl_permissions/bad_perms_pkg-1.0-py3-none-any.whl
```

Verify the permissions are set correctly:
```bash
zipinfo -l tests/pypi/whl_permissions/bad_perms_pkg-1.0-py3-none-any.whl
```

You should see entries like:
```
?rw-------  2.0 unx  bad_perms_pkg/__init__.py
?rw-------  2.0 unx  bad_perms_pkg-1.0.dist-info/METADATA
```

The `?rw-------` indicates mode `000` for those files.

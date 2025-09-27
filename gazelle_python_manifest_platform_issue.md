# Platform-Specific Inconsistency in gazelle_python_manifest

## Problem Summary

The `gazelle_python_manifest` rule generates different manifest files depending on the platform where it's executed, breaking build hermicity across development environments and CI systems.

## Specific Issue

When running the same codebase:
- **Local (macOS)**: `bazel test //:gazelle_python_manifest.test` **PASSES**
- **CI (Linux)**: `bazel test //:gazelle_python_manifest.test` **FAILS** with:
  ```
  opencv_python_headless.libs.libopenblas-r0-f650aae0: opencv_python_headless
  FAIL: files "gazelle_python_manifest.generated_manifest" and "gazelle_python.yaml" differ
  ```

## Root Cause Analysis

### How gazelle_python_manifest Works

The `gazelle_python_manifest` rule doesn't just read `requirements.txt` - it **inspects the actual installed Python wheel files** in the Bazel `@pip` repository:

1. **Extracts wheel contents**: Python wheels (`.whl` files) are platform-specific ZIP archives
2. **Scans for native libraries**: Looks for bundled `.so` files (Linux), `.dylib` files (macOS), etc.
3. **Maps import names to packages**: Creates mappings like `cv2: opencv_python_headless`
4. **Includes native library mappings**: Adds entries for detected native libraries

## Practical Impact: Zero Functional Effects

The platform-specific native library mappings (e.g., `opencv_python_headless.libs.libopenblas-r0-f650aae0`) have **no practical impact** on Python development:

- **Real Python code never imports these**: Nobody writes `import opencv_python_headless.libs.libopenblas-r0-f650aae0`
- **Critical mappings unchanged**: `cv2: opencv_python_headless` works identically on all platforms
- **Native libraries auto-load**: When you `import cv2`, underlying .so files load automatically
- **Zero functional difference**: Python code behaves identically with or without these mappings

The issue is purely about **build hermiticity**, not functionality. Adding `ignore_native_libs=True` would solve the platform inconsistency with no practical downsides.

## Why Native Lib Mappings Exist

These native library mappings are generated for completeness/accuracy, not functional necessity. The Python generator finds .so files in the wheel and dutifully maps them, but:

1. Native libraries are auto-loaded: When you import cv2, the underlying native libraries (like OpenBLAS) are loaded automatically by the Python extension
2. No direct imports: Python code doesn't directly import .so files by their mangled names
3. Bazel doesn't need them: The actual dependency resolution for builds works through the main module mappings

### Platform-Specific Wheel Contents

The same Python package ships different wheels for different platforms:

**Linux wheel** (`opencv_python_headless-4.x.x-cp310-cp310-linux_x86_64.whl`):
```
opencv_python_headless/
├── cv2/
│   └── python-3.10/
└── opencv_python_headless.libs/
    ├── libopenblas-r0-f650aae0.so  ← Linux-specific OpenBLAS library
    ├── libgfortran-2e0d59d6.so.5
    └── ...other Linux native libs
```

**macOS wheel** (`opencv_python_headless-4.x.x-cp310-cp310-macosx_11_0_arm64.whl`):
```
opencv_python_headless/
├── cv2/
│   └── python-3.10/
└── opencv_python_headless.libs/
    └── ...different macOS native libs (uses Apple's Accelerate framework)
```

### Resulting Manifest Differences

**Linux CI generates**:
```yaml
modules_mapping:
  cv2: opencv_python_headless
  opencv_python_headless.libs.libopenblas-r0-f650aae0: opencv_python_headless  # ← This line
```

**macOS local generates**:
```yaml
modules_mapping:
  cv2: opencv_python_headless
  # Missing the OpenBLAS line because macOS wheel doesn't contain it
```

## Reproduction Steps

1. Have a Python project using `opencv-python-headless` with `gazelle_python_manifest`
2. Run `bazel run //:gazelle_python_manifest.update` on macOS → generates manifest A
3. Run the same command on Linux → generates manifest B
4. Compare: manifest B will have additional native library entries that manifest A lacks

## Demonstrated Platform Dependency

When attempting to force Linux platform selection on macOS:
```bash
bazel run //:gazelle_python_manifest.update --platforms=@io_bazel_rules_go//go/toolchain:linux_amd64
```

This **successfully downloads the Linux wheel** but fails with:
```
OSError: [Errno 8] Exec format error: '.../python_3_10_x86_64-unknown-linux-gnu/bin/python3'
```

This proves that platform specification controls which wheels are selected, but cross-platform execution is impossible.

## Impact

- **Breaks build hermicity**: Same source code produces different results on different platforms
- **CI/Local inconsistency**: Developers can't reproduce CI failures locally
- **Manual workarounds required**: Teams must either:
  - Accept platform-specific manifest files (not hermetic)
  - Generate manifests only in Linux containers
  - Manually maintain manifest consistency

## Current Workaround Attempts

### 1. Manual Override (Not Sustainable)
Manually adding the missing entries to the manifest file, but this breaks the "DO NOT EDIT" contract and gets overwritten.

### 2. Platform-Specific Generation (Partial Solution)
Generate the manifest only in CI/Linux environment and commit it, but this prevents local development from updating dependencies.

### 3. Container-Based Generation (Complex)
Use Docker/containers for manifest generation, but adds complexity to the development workflow.

## Proposed Solutions

### Option 1: Platform-Agnostic Mode
Add a configuration option to `gazelle_python_manifest` to ignore platform-specific native libraries:
```python
gazelle_python_manifest(
    name = "gazelle_python_manifest",
    modules_mapping = ":modules_map",
    pip_repository_name = "pip",
    ignore_native_libs = True,  # New option
)
```

### Option 2: Union Mode
Generate manifests that include native libraries from all target platforms, not just the current platform.

### Option 3: Explicit Platform Targeting
Allow specifying target platforms for manifest generation:
```python
gazelle_python_manifest(
    name = "gazelle_python_manifest",
    modules_mapping = ":modules_map",
    pip_repository_name = "pip",
    target_platforms = ["linux_x86_64", "macos_arm64"],
)
```

## Environment Details

- **rules_python version**: 1.6.1
- **rules_python_gazelle_plugin version**: 1.3.0
- **Python version**: 3.10
- **Package causing issue**: opencv-python-headless (but affects any package with platform-specific native libraries)
- **Bazel version**: Latest
- **Platforms tested**: macOS ARM64, Linux x86_64

## Related Issues

This is a fundamental design issue where `gazelle_python_manifest` prioritizes accuracy (detecting actual wheel contents) over hermicity (consistent results across platforms).

The behavior is **intentional but problematic** for teams requiring hermetic builds across different development platforms.

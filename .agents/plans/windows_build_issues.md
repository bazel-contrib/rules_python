# Windows Build Issues and Solutions in `rules_python`

This document tracks the technical problems, root causes, and solutions encountered when making Windows C/C++ extension (`py_extension`) and toolchain builds work reliably under Bazel and MSVC (`link.exe`).

---

## 1. MSVC `LNK1104: cannot open file 'python3.lib'` in `cc_shared_library`

### Problem
When linking C extension shared libraries (`.dll` / `.pyd`) on Windows using MSVC, `link.exe` failed with:
```
LINK : fatal error LNK1104: cannot open file 'python311.lib' (or 'python3.lib')
```

### Root Cause
1. **`cc_import` `system_provided = True`**: In `python/private/hermetic_runtime_repo_setup.bzl`, CPython import libraries (`python311.lib` / `python3.lib`) are declared with `cc_import(..., system_provided = True)`. `system_provided = True` signals to Bazel that the library is provided by the host environment, causing Bazel's `CcInfo` provider to intentionally suppress propagating the `.lib` file paths to `link.exe`.
2. **MSVC `#pragma comment` Directive**: When C/C++ source files `#include <Python.h>`, CPython's MSVC headers embed `#pragma comment(lib, "python311.lib")` into compiled `.obj` files. When `link.exe` runs, it reads the `#pragma comment` and searches for `python311.lib`. Because `system_provided = True` suppressed the `.lib` file path from linker flags, `link.exe` fails with `LNK1104`.

### Solution
In `py_extension_macro.bzl`, explicitly pass `$(locations //python/cc:current_py_cc_libs)` to `user_link_flags` and `Label("//python/cc:current_py_cc_libs")` to `additional_linker_inputs` on Windows:
```bzl
effective_user_link_flags = user_link_flags + select({
    "@platforms//os:macos": ["-undefined", "dynamic_lookup"],
    "@platforms//os:windows": ["$(locations //python/cc:current_py_cc_libs)"],
    "//conditions:default": [],
})
csl_kwargs["user_link_flags"] = effective_user_link_flags

csl_additional_linker_inputs = (additional_linker_inputs or []) + select({
    "@platforms//os:windows": [Label("//python/cc:current_py_cc_libs")],
    "//conditions:default": [],
})

cc_shared_library(
    name = csl_name,
    deps = final_csl_deps,
    additional_linker_inputs = csl_additional_linker_inputs,
    ...
)
```
This forces Bazel to resolve the exact path of the CPython import library in the execroot and pass it directly to `link.exe` as a user link flag and build input.

---

## 3. Symbol Exporting (`PyMODINIT_FUNC` vs `/EXPORT`)

### Problem
Passing explicit `/EXPORT:PyInit_<module_name>` link flags to `link.exe` was brittle and required manual module name string manipulation.

### Solution
CPython's `PyMODINIT_FUNC` macro on Windows expands to `__declspec(dllexport) PyObject*`. MSVC `link.exe` automatically detects `__declspec(dllexport)` symbols in `.obj` files listed in `cc_shared_library`'s `exports_filter` and generates the corresponding `.def` file. Explicit `/EXPORT` flags are unnecessary and were removed.

---

## 4. MSVC `LNK1107` from Raw `.dll` Files in Linker Inputs

### Problem
Passing raw `.dll` binaries directly to `link.exe` caused:
```
fatal error LNK1107: invalid or corrupt file: cannot read at 0x...
```

### Solution
MSVC `link.exe` expects import libraries (`.lib`), not executable `.dll` binaries. In `current_py_cc_libs.bzl`, filter `DefaultInfo.files` to include only linkable library files (`.lib` / `.a`) and exclude `.dll` files.

---

## 5. Removing Redundant `$(locations)` Flags

### Problem
`py_extension_macro.bzl` previously used `$(locations @rules_python//python/cc:current_py_cc_libs)` in `user_link_flags` and `additional_linker_inputs`.

### Solution
By including `current_py_cc_libs` in `deps` and `exports_filter` of `cc_shared_library`, Bazel's `CcInfo` mechanism natively propagates the import library to `link.exe` without manual `$(locations)` expansion.

---

## 6. Duplicate Label Error when `srcs`/`hdrs` are Omitted

### Problem
When `py_extension` targets omitted `srcs` and `hdrs` (relying solely on `deps`), Bazel failed with:
`Label '//python/private/cc:current_py_cc_libs_private_alias' is duplicated` in `deps` of `cc_shared_library`.

### Cause
When `srcs`/`hdrs` were not provided, `deps` already contained `current_py_cc_libs_private_alias`. `final_csl_deps` inherited `deps`, and unconditionally appending `current_py_cc_libs_private_alias` again caused a duplicate entry in `deps` of `cc_shared_library`.

### Solution
Only append `current_py_cc_libs_private_alias` to `final_csl_deps` when `srcs or hdrs` is True:
```bzl
if srcs or hdrs:
    csl_deps_with_win = final_csl_deps + select({
        "@platforms//os:windows": ["//python/private/cc:current_py_cc_libs_private_alias"],
        "//conditions:default": [],
    })
else:
    csl_deps_with_win = final_csl_deps
```

# Windows Build Issues and Solutions in `rules_python`

This document tracks the technical problems, root causes, and solutions encountered when making Windows C/C++ extension (`py_extension`) and toolchain builds work reliably under Bazel and MSVC (`link.exe`).

---

## 1. MSVC `LNK1104: cannot open file 'python3.lib'` in `cc_shared_library`

### Problem
When linking C extension shared libraries (`.dll` / `.pyd`) on Windows using MSVC, `link.exe` failed with:
```
LINK : fatal error LNK1104: cannot open file 'python3.lib'
```

### Root Cause
When C/C++ source files `#include <Python.h>`, CPython's headers include `#pragma comment(lib, "python3.lib")` (when `Py_LIMITED_API` is set) or `#pragma comment(lib, "python3xx.lib")`. MSVC embeds a `/DEFAULTLIB:python3.lib` directive inside the compiled `.obj` files.

When `cc_shared_library` links these `.obj` files into a `.dll`, `link.exe` attempts to locate `python3.lib`.
By default, `cc_shared_library` applies `exports_filter` to prune transitive dependencies. If `current_py_cc_libs` is only in `deps` of the internal `cc_library` (`_impl`) but not listed in `deps` or `exports_filter` of `cc_shared_library`, `cc_shared_library` prunes `current_py_cc_libs` from `link.exe`'s command-line inputs. As a result, `python3.lib` is omitted, causing `link.exe` to fail.

### Solution
In `py_extension_macro.bzl`, append `//python/private/cc:current_py_cc_libs_private_alias` to `deps` and `exports_filter` of `cc_shared_library` specifically on Windows:
```bzl
csl_deps_with_win = final_csl_deps + select({
    "@platforms//os:windows": ["//python/private/cc:current_py_cc_libs_private_alias"],
    "//conditions:default": [],
})
csl_kwargs["exports_filter"] = exports_filter if exports_filter != None else csl_deps_with_win

cc_shared_library(
    name = csl_name,
    deps = csl_deps_with_win,
    ...
)
```

---

## 2. Hardcoded Repository Labels in `exports_filter` under Bzlmod

### Problem
Hardcoded label strings like `"@rules_python//python/cc:current_py_cc_libs"` failed to match targets during Bzlmod execution because Bazel rewrites module repository names (e.g. `rules_python~~python~...`), causing `exports_filter` to miss the target and prune `python3.lib`.

### Solution
Use `str(Label("//python/cc:current_py_cc_libs"))`, `:__subpackages__`, or private alias targets (`//python/private/cc:current_py_cc_libs_private_alias`) so Starlark label expansion evaluates to canonical Bzlmod repository names.

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

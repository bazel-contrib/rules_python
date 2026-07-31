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

## 2. Hardcoded Repository Labels & Alias Dereferencing in `exports_filter` under Bzlmod

### Problem
1. Hardcoded label strings like `"@rules_python//python/cc:current_py_cc_libs"` failed to match targets during Bzlmod execution because Bazel rewrites module repository names (e.g. `rules_python~~python~...`), causing `exports_filter` to miss the target and prune `python3.lib`.
2. Furthermore, Bazel dereferences `alias` targets (such as `//python/private/cc:current_py_cc_libs_private_alias` pointing to `//python/cc:current_py_cc_libs`) when resolving target dependencies in `cc_shared_library`. If `exports_filter` only contains the alias target label string, `cc_shared_library` fails to match the dereferenced actual target label, filtering out `current_py_cc_libs` and omitting `python311.lib`.

### Solution
Use `str(Label("//python/cc:current_py_cc_libs"))` alongside `str(Label("//python/private/cc:current_py_cc_libs_private_alias"))` inside the macro body:
```bzl
py_cc_libs_alias = str(Label("//python/private/cc:current_py_cc_libs_private_alias"))
py_cc_libs_target = str(Label("//python/cc:current_py_cc_libs"))
win_exports_filter = select({
    "@platforms//os:windows": [py_cc_libs_target, py_cc_libs_alias],
    "//conditions:default": [],
})
csl_kwargs["exports_filter"] = exports_filter if exports_filter != None else (csl_deps_with_win + win_exports_filter)
```

> **Important Scoping Note**: `str(Label(...))` **must** be evaluated inside macro bodies (`def py_extension(...)`) rather than as top-level `.bzl` module constants. At top-level module load time, `str(Label(...))` bakes in the repo-root canonical prefix (`@@//...`). Evaluating `str(Label(...))` dynamically inside the macro body ensures `Label` stringification resolves in the caller's evaluation context (e.g. `@@rules_python+...`), matching `cc_shared_library`'s canonical target labels correctly.

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

# Windows MSVC Toolchains & Linking

## MSVC `#pragma comment(lib, ...)` Embedded References
* CPython's MSVC headers embed `#pragma comment(lib, "python3xx.lib")` into
  generated `.obj` files. MSVC `link.exe` automatically searches for
  `python3xx.lib` in library search paths during linking.
* **Citation**: [Microsoft Learn `comment` pragma](https://learn.microsoft.com/en-us/cpp/preprocessor/comment-c-cpp)
  (*"Places a library-search record in the object file... The linker searches for
  this library the same way as if you had named it on the command line"*).

## PEP 3149 ABI Tag Prefix (`cp` vs. `cpython-`)
* Windows CPython ABI tags use the `cp` prefix (e.g., `cp311`, `cp312t`)
  whereas POSIX platforms use `cpython-` (e.g., `cpython-311`).
* **Citation**: [PEP 3149 — ABI version tagged .so files](https://peps.python.org/pep-3149/)
  (*"The tag starts with `cpython-` followed by the Python major and minor version
  without dots... followed by build flags"*).

## Windows Platform Tag Derivation
* Windows platform tags for Python C extensions evaluate to `win_amd64`
  (x86_64/amd64), `win_arm64` (aarch64/arm64), or `win32` (32-bit x86).
* **`platform.machine()` Normalization**: On Windows,
  `platform.machine()` returns uppercase (`"AMD64"`, `"ARM64"`). Always
  normalize with `.lower()` when deriving PEP 508 markers or resolving platform
  tags.
* **Citation**: [PEP 425 — Compatibility Tags for Built Distributions](https://peps.python.org/pep-0425/).

## Windows CPython SOABI & ABI Infix Support
* CPython on Windows natively supports loading ABI-tagged `.pyd` files
  containing platform tags (e.g., `foo.cp314-win_amd64.pyd`,
  `foo.cp311-win_amd64.pyd`).
* SOABI on Windows includes both the ABI prefix and platform tag (e.g.,
  `cp311-win_amd64`).

## Extended Paths (`\\?\`)
* **Test Path Lengths**: Keep source directories short so MSVC `cl.exe` params
  files stay under 260 chars (`MAX_PATH`, avoids `D8022`). Rely on runfiles
  expansion (`.exe.runfiles/_main/...`) to exceed `MAX_PATH` at runtime.
* **No `..` Segments**: Win32 ignores `..` on `\\?\` paths. Always call
  `os.path.normpath(...)` before accessing files (e.g., wheel `RECORD` paths).
* **Comparing Executables**: Subprocesses may drop `\\?\` or `\\?\UNC\`
  prefixes. Strip prefixes and compare via
  `os.path.normcase(os.path.normpath(...))`.

## Windows Wheel Script Rewriting & RECORD Generation
* **Shebang Rewriting**: On Windows, scripts that use shebangs are rewritten into
  wrapper scripts with `.bat` file extensions.
* **RECORD File Paths**: In `RECORD` files, append `.bat` only to the
  shebang-rewritten scripts. Leave all other script paths unchanged.


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
* **Citation**: [PEP 425 — Compatibility Tags for Built Distributions](https://peps.python.org/pep-0425/).

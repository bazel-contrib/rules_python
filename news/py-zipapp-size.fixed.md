(zipapp) Reduced self-contained archive sizes by preserving Python executable
symlinks and omitting shared `libpython` files when the hermetic interpreter
includes Python statically.
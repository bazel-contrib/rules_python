(pypi) Downloaded wheels are removed after extraction when their original
archive can be fetched independently. The existing `whl` and `whl_file` targets
fetch the archive from a separate repository on demand. Matching patches are
applied in the separate wheel-file repository, which also supplies the patched
archive for extraction. Wheels built from source retain their existing archive
behavior.

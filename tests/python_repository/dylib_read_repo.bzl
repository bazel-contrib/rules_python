"""Checks `dylib_id_is_rpath` on a dylib read back with `rctx.read`.

The unit tests build their input with string escapes; this repo writes
`HIGH_BYTES_DYLIB` to disk and reads it the way `python_repository` reads the
runtime's dylib, so bytes >= 0x80 go through `rctx.read`.
"""

load("//python/private:python_repository.bzl", "dylib_id_is_rpath")  # buildifier: disable=bzl-visibility
load(":macho.bzl", "DYLIB", "HIGH_BYTES_DYLIB")

def _dylib_read_repo_impl(rctx):
    # legacy_utf8 = False writes each character as one byte instead of
    # UTF-8 encoding the ones >= 0x80; Bazel 9 always does this.
    rctx.file(DYLIB, HIGH_BYTES_DYLIB, executable = False, legacy_utf8 = False)
    rctx.file("result.json", json.encode({
        "dylib_id_is_rpath": dylib_id_is_rpath(rctx.read(DYLIB), DYLIB),
    }))
    rctx.file("BUILD.bazel", 'exports_files(["{}", "result.json"])'.format(DYLIB))

dylib_read_repo = repository_rule(
    implementation = _dylib_read_repo_impl,
)

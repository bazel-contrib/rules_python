"""Unit tests for python_repository.bzl."""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private:python_repository.bzl", "dylib_id_is_rpath")  # buildifier: disable=bzl-visibility
load(
    ":macho.bzl",
    "DYLIB",
    "FAT_MAGIC",
    "HIGH_BYTES_DYLIB",
    "LC_ID_DYLIB",
    "LC_LOAD_DYLIB",
    "MH_MAGIC",
    "dylib_command",
    "header",
)

_tests = []

_RPATH_ID = dylib_command(LC_ID_DYLIB, "@rpath/" + DYLIB)
_BUILD_HOST_ID = dylib_command(LC_ID_DYLIB, "/install/lib/" + DYLIB)
_LOAD_LIBSYSTEM = dylib_command(LC_LOAD_DYLIB, "/usr/lib/libSystem.B.dylib")

# Load command counts and sizes, as the little-endian bytes `header` takes.
_ONE = "\001"
_TWO = "\002"
_64_BYTES = "\100"
_128_BYTES = "\200"

def _test_rpath_id(env):
    contents = header(_ONE, _64_BYTES) + _RPATH_ID
    env.expect.that_bool(dylib_id_is_rpath(contents, DYLIB)).equals(True)

_tests.append(_test_rpath_id)

def _test_rpath_id_after_other_command(env):
    contents = header(_TWO, _128_BYTES) + _LOAD_LIBSYSTEM + _RPATH_ID
    env.expect.that_bool(dylib_id_is_rpath(contents, DYLIB)).equals(True)

_tests.append(_test_rpath_id_after_other_command)

def _test_high_bytes(env):
    # `cmdsize` 0x88 and `sizeofcmds` 0xc8 must decode to 136 and 200.
    env.expect.that_bool(dylib_id_is_rpath(HIGH_BYTES_DYLIB, DYLIB)).equals(True)

_tests.append(_test_high_bytes)

def _test_build_host_id(env):
    contents = header(_ONE, _64_BYTES) + _BUILD_HOST_ID
    env.expect.that_bool(dylib_id_is_rpath(contents, DYLIB)).equals(False)

_tests.append(_test_build_host_id)

def _test_rpath_name_outside_id_command(env):
    # The id is wrong, but `@rpath/<dylib>` appears in a load command and as a
    # plain string; neither must count as the id.
    contents = (
        header(_TWO, _128_BYTES) +
        _BUILD_HOST_ID +
        dylib_command(LC_LOAD_DYLIB, "@rpath/" + DYLIB) +
        "@rpath/" + DYLIB + "\000"
    )
    env.expect.that_bool(dylib_id_is_rpath(contents, DYLIB)).equals(False)

_tests.append(_test_rpath_name_outside_id_command)

def _test_id_command_outside_load_command_area(env):
    # A well-formed LC_ID_DYLIB naming `@rpath/<dylib>` right after the
    # `sizeofcmds` bytes of load commands is data, not the id.
    contents = header(_ONE, _64_BYTES) + _LOAD_LIBSYSTEM + _RPATH_ID
    env.expect.that_bool(dylib_id_is_rpath(contents, DYLIB)).equals(False)

    # Same when `ncmds` counts it but `sizeofcmds` does not cover it.
    contents = header(_TWO, _64_BYTES) + _LOAD_LIBSYSTEM + _RPATH_ID
    env.expect.that_bool(dylib_id_is_rpath(contents, DYLIB)).equals(False)

_tests.append(_test_id_command_outside_load_command_area)

def _test_truncated(env):
    # `sizeofcmds` reaches past the end of the file.
    contents = header(_ONE, _128_BYTES) + _RPATH_ID
    env.expect.that_bool(dylib_id_is_rpath(contents, DYLIB)).equals(False)

_tests.append(_test_truncated)

def _test_other_dylib_name(env):
    # `@rpath/libpython3.13.dylib` must not match `@rpath/libpython3.13d.dylib`
    # or a longer name sharing its prefix.
    contents = header(_ONE, _64_BYTES) + dylib_command(LC_ID_DYLIB, "@rpath/" + DYLIB + ".bak")
    env.expect.that_bool(dylib_id_is_rpath(contents, DYLIB)).equals(False)
    contents = header(_ONE, _64_BYTES) + _RPATH_ID
    env.expect.that_bool(dylib_id_is_rpath(contents, "libpython3.13d.dylib")).equals(False)

_tests.append(_test_other_dylib_name)

def _test_not_thin_macho64(env):
    # Universal and 32-bit binaries are left to `install_name_tool`.
    for magic in (FAT_MAGIC, MH_MAGIC):
        contents = header(_ONE, _64_BYTES, magic = magic) + _RPATH_ID
        env.expect.that_bool(dylib_id_is_rpath(contents, DYLIB)).equals(False)

_tests.append(_test_not_thin_macho64)

def python_repository_test_suite(name):
    test_suite(
        name = name,
        basic_tests = _tests,
    )

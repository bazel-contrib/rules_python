"""Unit tests for python_repository.bzl."""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private:python_repository.bzl", "dylib_id_is_rpath")  # buildifier: disable=bzl-visibility

_tests = []

_DYLIB = "libpython3.13.dylib"

# A mach_header_64: magic, then 28 bytes the check does not read.
_HEADER = "\317\372\355\376" + "\000" * 28

def _dylib_command(cmd, name):
    # cmd, cmdsize (unchecked), name.offset = 24, timestamp, current_version,
    # compatibility_version, then the NUL-terminated name.
    return cmd + "\070\000\000\000" + "\030\000\000\000" + "\000" * 12 + name + "\000"

_LC_ID_DYLIB = "\015\000\000\000"
_LC_LOAD_DYLIB = "\014\000\000\000"

def _test_rpath_id(env):
    contents = _HEADER + _dylib_command(_LC_ID_DYLIB, "@rpath/" + _DYLIB)
    env.expect.that_bool(dylib_id_is_rpath(contents, _DYLIB)).equals(True)

_tests.append(_test_rpath_id)

def _test_build_host_id(env):
    contents = _HEADER + _dylib_command(_LC_ID_DYLIB, "/install/lib/" + _DYLIB)
    env.expect.that_bool(dylib_id_is_rpath(contents, _DYLIB)).equals(False)

_tests.append(_test_build_host_id)

def _test_rpath_name_outside_id_command(env):
    # The id is wrong, but `@rpath/<dylib>` appears in a load command and as a
    # plain string; neither must count as the id.
    contents = (
        _HEADER +
        _dylib_command(_LC_ID_DYLIB, "/install/lib/" + _DYLIB) +
        _dylib_command(_LC_LOAD_DYLIB, "@rpath/" + _DYLIB) +
        "@rpath/" + _DYLIB + "\000"
    )
    env.expect.that_bool(dylib_id_is_rpath(contents, _DYLIB)).equals(False)

_tests.append(_test_rpath_name_outside_id_command)

def _test_other_dylib_name(env):
    # `@rpath/libpython3.13.dylib` must not match `@rpath/libpython3.13d.dylib`
    # or a longer name sharing its prefix.
    contents = _HEADER + _dylib_command(_LC_ID_DYLIB, "@rpath/" + _DYLIB + ".bak")
    env.expect.that_bool(dylib_id_is_rpath(contents, _DYLIB)).equals(False)
    contents = _HEADER + _dylib_command(_LC_ID_DYLIB, "@rpath/" + _DYLIB)
    env.expect.that_bool(dylib_id_is_rpath(contents, "libpython3.13d.dylib")).equals(False)

_tests.append(_test_other_dylib_name)

def _test_not_thin_macho64(env):
    # A universal binary starts with the big-endian FAT_MAGIC.
    contents = "\312\376\272\276" + "\000" * 28 + _dylib_command(_LC_ID_DYLIB, "@rpath/" + _DYLIB)
    env.expect.that_bool(dylib_id_is_rpath(contents, _DYLIB)).equals(False)

_tests.append(_test_not_thin_macho64)

def python_repository_test_suite(name):
    test_suite(
        name = name,
        basic_tests = _tests,
    )

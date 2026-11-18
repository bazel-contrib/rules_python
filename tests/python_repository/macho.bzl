"""Builds synthetic Mach-O files for the python_repository tests.

Bytes are written with octal escapes, which is what `rctx.read` produces for
the same bytes on disk. Multi-byte fields are little-endian.
"""

DYLIB = "libpython3.13.dylib"

MH_MAGIC = "\316\372\355\376"
MH_MAGIC_64 = "\317\372\355\376"
FAT_MAGIC = "\312\376\272\276"

LC_LOAD_DYLIB = "\014\000\000\000"
LC_ID_DYLIB = "\015\000\000\000"
LC_SEGMENT_64 = "\031\000\000\000"

def u32(value):
    """Pads a little-endian value given as 1 to 4 bytes to a uint32."""
    return value + "\000" * (4 - len(value))

def header(ncmds, sizeofcmds, magic = MH_MAGIC_64):
    """A mach_header_64 with the given `ncmds` and `sizeofcmds` bytes."""

    # magic, cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags, reserved
    return magic + "\000" * 12 + u32(ncmds) + u32(sizeofcmds) + "\000" * 8

def dylib_command(cmd, name):
    """A 64-byte (0o100) dylib_command whose name starts at offset 24."""
    if len(name) >= 40:
        fail("name too long for a 64-byte dylib_command: " + name)

    # cmd, cmdsize, name.offset, timestamp, current_version,
    # compatibility_version, then the NUL-padded name.
    return cmd + u32("\100") + u32("\030") + "\000" * 12 + name + "\000" * (40 - len(name))

# A 136-byte (0x88) load command of 0xff bytes, so that `cmdsize` and the
# `sizeofcmds` that includes it have bytes >= 0x80.
SEGMENT_COMMAND = LC_SEGMENT_64 + u32("\210") + "\377" * 128

# A dylib whose id is `@rpath/<DYLIB>`, after a command with bytes >= 0x80.
# `sizeofcmds` is 136 + 64 = 200 (0xc8).
HIGH_BYTES_DYLIB = (
    header("\002", "\310") +
    SEGMENT_COMMAND +
    dylib_command(LC_ID_DYLIB, "@rpath/" + DYLIB)
)

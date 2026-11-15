"""Default `uv` toolchain configuration for WORKSPACE.

Under bzlmod, the equivalent defaults are the `uv.default()` calls in
`MODULE.bazel`. Keep the values here in sync with them.
"""

# LINT.IfChange(uv_defaults)
DEFAULT_VERSION = "0.13.5"

DEFAULT_BASE_URL = "https://github.com/astral-sh/uv/releases/download"
# LINT.ThenChange(//MODULE.bazel:uv_defaults)

def _platform(platform, *, os, cpu):
    # Same shape as the platform structs `set_config` creates.
    return struct(
        name = platform.replace("-", "_").lower(),
        compatible_with = [
            str(Label("@platforms//os:" + os)),
            str(Label("@platforms//cpu:" + cpu)),
        ],
        target_settings = [],
    )

# LINT.IfChange(uv_platforms)
DEFAULT_PLATFORMS = {
    platform: _platform(platform, os = os, cpu = cpu)
    for platform, os, cpu in [
        ("aarch64-apple-darwin", "macos", "aarch64"),
        ("aarch64-unknown-linux-gnu", "linux", "aarch64"),
        ("powerpc64le-unknown-linux-gnu", "linux", "ppc64le"),
        ("s390x-unknown-linux-gnu", "linux", "s390x"),
        ("riscv64-unknown-linux-gnu", "linux", "riscv64"),
        ("x86_64-apple-darwin", "macos", "x86_64"),
        ("x86_64-pc-windows-msvc", "windows", "x86_64"),
        ("x86_64-unknown-linux-gnu", "linux", "x86_64"),
    ]
}
# LINT.ThenChange(//MODULE.bazel:uv_platforms)

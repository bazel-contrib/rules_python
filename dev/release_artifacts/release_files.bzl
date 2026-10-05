"""Macro to build the files for a release and list where they are."""

load("//python/private:common_labels.bzl", "labels")  # buildifier: disable=bzl-visibility

_FEATURES = "//command_line_option:features"
_RUSTC_FLAGS = "@rules_rust//rust/settings:extra_rustc_flags"

def _release_transition_impl(settings, attr):
    features = []
    rustc_flags = []
    if attr.target_os == "linux":
        # Rust links glibc dynamically, so the files would require at least
        # the build machine's glibc version. Link it statically so they run on
        # older distros too. The gold linker can't link static glibc, so use
        # bfd.
        rustc_flags = [
            "-Ctarget-feature=+crt-static",
            "-Clink-arg=-fuse-ld=bfd",
        ]
    elif attr.target_os == "windows":
        # Statically link the C runtime so that the VC++ redistributable isn't
        # required.
        features = ["static_link_msvcrt"]
        rustc_flags = ["-Ctarget-feature=+crt-static"]
    return {
        "//command_line_option:compilation_mode": "opt",
        # Only affects macOS. Without it, the minimum OS version is the build
        # machine's SDK version.
        "//command_line_option:macos_minimum_os": "11.0",
        _FEATURES: settings[_FEATURES] + features,
        _RUSTC_FLAGS: settings[_RUSTC_FLAGS] + rustc_flags,
    }

_release_transition = transition(
    implementation = _release_transition_impl,
    inputs = [_FEATURES, _RUSTC_FLAGS],
    outputs = [
        "//command_line_option:compilation_mode",
        "//command_line_option:macos_minimum_os",
        _FEATURES,
        _RUSTC_FLAGS,
    ],
)

def _release_files_impl(ctx):
    manifest = ctx.actions.declare_file(ctx.label.name + ".txt")
    ctx.actions.write(
        output = manifest,
        # End every line with "\n", including the last: `while read` loops skip
        # an unterminated last line, and build.sh adds a line after the paths.
        content = "".join([file.path + "\n" for file in ctx.files.srcs]),
    )
    return [DefaultInfo(files = depset([manifest] + ctx.files.srcs))]

_release_files = rule(
    implementation = _release_files_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            cfg = _release_transition,
            doc = "The files to build and list.",
        ),
        "target_os": attr.string(
            doc = "The OS that the files are built for. Set by the macro.",
        ),
    },
)

def release_files(name, srcs, **kwargs):
    """Builds files for a release and writes their paths to `<name>.txt`.

    The files are built with release settings: optimized, and linked so that
    they run on older OS versions than the build machine's, without extra
    runtime libraries.

    The paths, one per line, are relative to the execroot, e.g.
    `bazel-out/k8-opt-ST-1234/bin/foo/foo`. Paths of generated files also
    resolve from the workspace root through the `bazel-out` convenience
    symlink. This lets scripts find the files without running `bazel cquery`,
    which re-analyzes the build.

    Args:
        name: The target name.
        srcs: The files to build and list.
        **kwargs: Additional attributes for the rule.
    """
    _release_files(
        name = name,
        srcs = srcs,
        target_os = select({
            Label("@platforms//os:linux"): "linux",
            labels.PLATFORMS_OS_WINDOWS: "windows",
            "//conditions:default": "",
        }),
        **kwargs
    )

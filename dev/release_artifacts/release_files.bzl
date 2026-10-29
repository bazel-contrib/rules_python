"""Macro and rule to build the files for a release and list where they are."""

load("//python/private:common_labels.bzl", "labels")  # buildifier: disable=bzl-visibility

_FEATURES = "//command_line_option:features"
_RUSTC_FLAGS = "@rules_rust//rust/settings:extra_rustc_flags"

_ReleaseFilesInfo = provider(
    doc = "Files built by _release_files, excluding the .txt manifest.",
    fields = ["files"],
)

def _release_transition_impl(settings, attr):
    features = []
    rustc_flags = []
    if attr.target_os == "linux":
        # Rust links glibc dynamically, so the files would require at least
        # the build machine's glibc version. Link it statically so they run on
        # older distros too. Rust links musl statically for most CPUs, but not
        # all, e.g. riscv64.
        rustc_flags = ["-Ctarget-feature=+crt-static"]
        if attr.target_libc != "musl":
            # The gold linker can't link static glibc, so use bfd.
            rustc_flags.append("-Clink-arg=-fuse-ld=bfd")
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

def _triple(ctx):
    cpu = ctx.attr.target_cpu
    os = ctx.attr.target_os
    if os == "macos":
        return "{}-apple-darwin".format(cpu)
    if os == "windows":
        return "{}-pc-windows-msvc".format(cpu)
    if os == "linux":
        if cpu == "armv7":
            return "{}-unknown-linux-musleabihf".format(cpu)
        if ctx.attr.target_libc == "musl":
            return "{}-unknown-linux-musl".format(cpu)
        return "{}-unknown-linux-gnu".format(cpu)
    fail("Unsupported target_os: {}".format(os))

def _release_files_impl(ctx):
    triple = _triple(ctx)
    files = []
    for src in ctx.files.srcs:
        if src.extension:
            stem = src.basename[:-len(src.extension) - 1]
            ext = "." + src.extension
        else:
            stem = src.basename
            ext = ""
        out = ctx.actions.declare_file("{}-{}{}".format(stem, triple, ext))
        ctx.actions.symlink(
            output = out,
            target_file = src,
            is_executable = True,
        )
        files.append(out)

    manifest = ctx.actions.declare_file(ctx.label.name + ".txt")
    ctx.actions.write(
        output = manifest,
        # End every line with "\n", including the last: `while read` loops skip
        # an unterminated last line, and build.sh adds a line after the paths.
        content = "".join([file.path + "\n" for file in files]),
    )
    return [
        DefaultInfo(files = depset([manifest] + files)),
        _ReleaseFilesInfo(files = files),
    ]

_release_files = rule(
    implementation = _release_files_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            cfg = _release_transition,
            doc = "The files to build and list.",
        ),
        "target_cpu": attr.string(
            doc = "The CPU that the files are built for. Set by the macro.",
            mandatory = True,
        ),
        "target_libc": attr.string(
            doc = "The libc that the files are built for. Set by the macro.",
        ),
        "target_os": attr.string(
            doc = "The OS that the files are built for. Set by the macro.",
            mandatory = True,
        ),
    },
)

def release_files(name, srcs, **kwargs):
    """Builds files for a release and writes their paths to `<name>.txt`.

    The files are named `<stem>-<triple>[.<ext>]` and built for the target
    platform (`--platforms`), with release settings for its OS and libc:
    optimized, and linked so that they run on older OS versions than the build
    machine's, without extra runtime libraries.

    The paths, one per line, are relative to the execroot, e.g.
    `bazel-out/k8-opt/bin/dev/release_artifacts/foo-x86_64-unknown-linux-gnu`.
    Paths of generated files also resolve from the workspace root through the
    `bazel-out` convenience symlink. This lets scripts find the files without
    running `bazel cquery`, which re-analyzes the build.

    Args:
        name: The target name.
        srcs: The files to build and list.
        **kwargs: Additional attributes for the rule.
    """
    _release_files(
        name = name,
        srcs = srcs,
        target_cpu = select({
            Label("@platforms//cpu:aarch64"): "aarch64",
            Label("@platforms//cpu:armv7"): "armv7",
            Label("@platforms//cpu:ppc64le"): "powerpc64le",
            Label("@platforms//cpu:riscv64"): "riscv64gc",
            Label("@platforms//cpu:x86_32"): "i686",
            Label("@platforms//cpu:x86_64"): "x86_64",
        }),
        target_libc = select({
            "//dev/platforms:musl": "musl",
            "//conditions:default": "",
        }),
        target_os = select({
            Label("@platforms//os:linux"): "linux",
            labels.PLATFORMS_OS_MACOS: "macos",
            labels.PLATFORMS_OS_WINDOWS: "windows",
        }),
        **kwargs
    )

def _platforms_transition_impl(_settings, attr):
    # A split transition: one configuration per platform, keyed by its label.
    return {
        str(platform): {"//command_line_option:platforms": str(platform)}
        for platform in attr.platforms
    }

_platforms_transition = transition(
    implementation = _platforms_transition_impl,
    inputs = [],
    outputs = ["//command_line_option:platforms"],
)

def _cross_compiled_files_impl(ctx):
    # Without platforms, the transition leaves src in this target's
    # configuration, so skip it.
    if not ctx.attr.platforms:
        return [DefaultInfo()]

    # With a transition, ctx.attr.src is a list: one target per platform.
    files = []
    for src in ctx.attr.src:
        files.extend(src[_ReleaseFilesInfo].files)
    manifest = ctx.actions.declare_file(ctx.label.name + ".txt")
    ctx.actions.write(
        output = manifest,
        # End every line with "\n", including the last: `while read` loops skip
        # an unterminated last line, and build.sh adds a line after the paths.
        content = "".join([file.path + "\n" for file in files]),
    )
    return [DefaultInfo(files = depset([manifest] + files))]

cross_compiled_files = rule(
    implementation = _cross_compiled_files_impl,
    doc = """
Builds `src` for each platform in `platforms`, in one build.

`--platforms` selects only one target platform per build. With no platforms,
this builds nothing.
""",
    attrs = {
        "platforms": attr.label_list(
            doc = "The platforms to build `src` for.",
            providers = [platform_common.PlatformInfo],
        ),
        "src": attr.label(
            cfg = _platforms_transition,
            doc = "The target to build.",
            mandatory = True,
            providers = [_ReleaseFilesInfo],
        ),
    },
)

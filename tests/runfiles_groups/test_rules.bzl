"""Rules for testing the runfiles group describers."""

load("@rules_runfiles_group//runfiles_group:identity_packager.bzl", "RunfilesGroupIdentityInfo", "runfiles_groups_identity_aspect")
load("@rules_runfiles_group//runfiles_group:lib.bzl", "runfiles_groups")

def _outputs_only_impl(ctx):
    files = [ctx.actions.declare_file(ctx.label.name + suffix) for suffix in (".a", ".b")]
    for f in files:
        ctx.actions.write(f, "")
    return [DefaultInfo(files = depset(files))]

# Default outputs, no runfiles.
outputs_only = rule(implementation = _outputs_only_impl)

def _outputs_and_runfiles_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".out")
    runfile = ctx.actions.declare_file(ctx.label.name + ".runfile")
    ctx.actions.write(output, "")
    ctx.actions.write(runfile, "")
    return [DefaultInfo(files = depset([output]), runfiles = ctx.runfiles([runfile]))]

# Default outputs and runfiles that differ.
outputs_and_runfiles = rule(implementation = _outputs_and_runfiles_impl)

ResolvedGroupsInfo = provider(
    doc = "A binary's runfiles groups, as a packager would resolve them.",
    fields = {
        "groups": """
:type: dict[str, struct]

By group name: `merge_affinity`, `do_not_merge`, and `root_symlinks`, the paths
of the group's root symlinks.
""",
    },
)

_AspectHintsInfo = provider(
    doc = "A binary's aspect_hints.",
    fields = {"aspect_hints": "list[Target]"},
)

def _aspect_hints_aspect_impl(_target, ctx):
    return [_AspectHintsInfo(aspect_hints = ctx.rule.attr.aspect_hints)]

_aspect_hints_aspect = aspect(implementation = _aspect_hints_aspect_impl)

def _resolved_groups_impl(ctx):
    binary = ctx.attr.binary
    resolved = runfiles_groups.finalize(
        ctx,
        binary[RunfilesGroupIdentityInfo],
        runfiles_groups.IDENTITY_OPS,
        aspect_hints = binary[_AspectHintsInfo].aspect_hints,
    )
    groups = {}
    for group in resolved.groups:
        runfiles = runfiles_groups.runfiles(ctx, group.handle)
        groups[runfiles_groups.name_str(group.name)] = struct(
            merge_affinity = group.merge_affinity,
            do_not_merge = group.do_not_merge,
            root_symlinks = [link.path for link in runfiles.root_symlinks.to_list()],
        )
    return [ResolvedGroupsInfo(groups = groups)]

# Resolves a binary's groups with the identity packager, applying the
# transforms in the binary's aspect_hints like a real packager does.
resolved_groups = rule(
    implementation = _resolved_groups_impl,
    attrs = {
        "binary": attr.label(aspects = [_aspect_hints_aspect, runfiles_groups_identity_aspect]),
    },
)

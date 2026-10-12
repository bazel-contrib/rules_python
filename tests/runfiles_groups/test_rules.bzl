"""Rules with shapes of `data` that the runfiles group describers must cover."""

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

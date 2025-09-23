"""Implementation of the py_extension rule."""

def _py_extension_impl(ctx):
    pass

py_extension = rule(
    implementation = _py_extension_impl,
)

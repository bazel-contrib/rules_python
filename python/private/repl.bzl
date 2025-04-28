"""Implementation of the rules to expose a REPL."""

load("//python:py_binary.bzl", _py_binary = "py_binary")

def _generate_repl_main_impl(ctx):
    stub_repo = ctx.attr.stub.label.repo_name or ctx.workspace_name
    stub_path = "/".join([stub_repo, ctx.file.stub.short_path])

    # Point the generated main file at the stub.
    ctx.actions.expand_template(
        template = ctx.file._template,
        output = ctx.outputs.out,
        substitutions = {
            "%stub_path%": stub_path,
        },
    )

_generate_repl_main = rule(
    implementation = _generate_repl_main_impl,
    attrs = {
        "out": attr.output(
            mandatory = True,
            doc = "The path to the file to generate.",
        ),
        "stub": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = ("The stub responsible for actually invoking the final shell. " +
                   "See the \"Customizing the REPL\" docs for details."),
        ),
        "_template": attr.label(
            default = "//python/private:repl_template.py",
            allow_single_file = True,
            doc = "The template to use for generating `out`.",
        ),
    },
    doc = """\
Generates a "main" script for a py_binary target that starts a Python REPL.

The template is designed to take care of the majority of the logic. The user
customizes the exact shell that will be started via the stub. The stub is a
simple shell script that imports the desired shell and then executes it.
""",
)

def py_repl_binary(name, stub, deps = [], data = [], **kwargs):
    """A py_binary target that executes a REPL when run.

    The stub is the script that ultimately decides which shell the REPL will run.
    It can be as simple as this:

        import code
        code.interact()

    Or it can load something like IPython instead.

    Args:
        name: Name of the generated py_binary target.
        stub: The script that invokes the shell.
        deps: The dependencies of the py_binary.
        data: The runtime dependencies of the py_binary.
        **kwargs: Forwarded to the py_binary.
    """
    _generate_repl_main(
        name = "%s_py" % name,
        stub = stub,
        out = "%s.py" % name,
    )

    _py_binary(
        name = name,
        srcs = [
            ":%s.py" % name,
        ],
        data = data + [
            stub,
        ],
        deps = deps + [
            "//python/runfiles",
        ],
        **kwargs
    )

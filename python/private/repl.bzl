"""Implementation of the rules to expose a REPL."""

load("//python:py_binary.bzl", "py_binary")

def _generate_repl_main_impl(ctx):
    stub_repo = ctx.attr.stub.label.repo_name or ctx.workspace_name
    stub_path = "/".join([stub_repo, ctx.file.stub.short_path])

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
)

def py_repl_binary(name, stub, deps = [], data = [], **kwargs):
    """A 
    _generate_repl_main(
        name = "%s_py" % name,
        stub = stub,
        out = "%s.py" % name,
    )

    py_binary(
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

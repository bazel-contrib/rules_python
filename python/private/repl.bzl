load("//python:py_binary.bzl", "py_binary")

def _generate_repl_main_impl(ctx):
    stub_repo = ctx.attr.src.label.repo_name or ctx.workspace_name
    stub_path = "/".join([stub_repo, ctx.file.src.short_path])

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
        ),
        "src": attr.label(
            mandatory = True,
            allow_single_file = True,
        ),
        "_generator": attr.label(
            default = "//python/private:repl_main_generator",
            executable = True,
            cfg = "exec",
        ),
        "_template": attr.label(
            default = "//python/private:repl_template.py",
            allow_single_file = True,
        ),
    },
)

def py_repl_binary(name, stub, deps=[], data=[], **kwargs):
    _generate_repl_main(
        name = "%s_py" % name,
        src = stub,
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
        **kwargs,
    )

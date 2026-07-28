"""Rule for generating venv entry point scripts."""

load("//python/private:attributes.bzl", "WINDOWS_CONSTRAINTS_ATTRS")
load("//python/private:common.bzl", "is_windows_platform")
load("//python/private:rule_builders.bzl", "ruleb")

def _venv_entry_point_impl(ctx):
    is_windows = is_windows_platform(ctx)

    out_name = ctx.label.name
    python_exe = ""
    if is_windows:
        out_name += ".bat"
        python_exe = "pythonw.exe" if ctx.attr.group == "gui_scripts" else "python.exe"

    out = ctx.actions.declare_file(out_name)

    ctx.actions.expand_template(
        template = ctx.file._template,
        output = out,
        substitutions = {
            "{ATTRIBUTE}": ctx.attr.attribute,
            "{MODULE}": ctx.attr.module,
            "{PYTHON_EXE}": python_exe,
        },
        is_executable = True,
    )

    return [DefaultInfo(
        files = depset([out]),
        executable = out,
    )]

_builder = ruleb.Rule(
    implementation = _venv_entry_point_impl,
    executable = True,
)
_builder.attrs.update({
    "attribute": attr.string(mandatory = False, doc = "The attribute to call"),
    "extras": attr.string(mandatory = False, doc = "The extras for the entry point"),
    "group": attr.string(mandatory = False, doc = "The entry point group (e.g. console_scripts)"),
    "module": attr.string(mandatory = True, doc = "The module to import"),
    "_template": attr.label(
        default = Label("//python/private/pypi:venv_entry_point_template"),
        allow_single_file = True,
    ),
})
_builder.attrs.update(WINDOWS_CONSTRAINTS_ATTRS)

venv_entry_point = _builder.build()

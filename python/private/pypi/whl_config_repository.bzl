""

load("//python/private:text_util.bzl", "render")

def _impl(rctx):
    rctx.file("BUILD.bazel", "")
    rctx.template(
        "config.bzl",
        rctx.attr._config_template,
        substitutions = {
            "%%PACKAGES%%": render.dict(rctx.attr.whl_map, value_repr = lambda x: "None"),
        },
    )

whl_config_repository = repository_rule(
    attrs = {
        "whl_map": attr.string_dict(
            mandatory = True,
            doc = """\
The wheel map where values are json.encoded strings of the whl_map constructed
in the pip.parse tag class.
""",
        ),
        "_config_template": attr.label(
            default = ":config.bzl.tmpl.bzlmod",
        ),
    },
    doc = """A rule for WORKSPACE to ensure correct whl_repository configuration. PRIVATE USE ONLY.""",
    implementation = _impl,
)

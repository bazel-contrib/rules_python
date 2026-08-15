""

load("//python/private:repo_utils.bzl", "REPO_DEBUG_ENV_VAR", "repo_utils")
load(":generate_whl_library_build_bazel.bzl", "generate_whl_library_build_bazel")
load(":pep508_requirement.bzl", "requirement")

# Reusable common attributes for generating BUILD.bazel from Requires-Dist in the wheel METADATA.
whl_deps_attrs = {
    "config_load": attr.string(
        doc = "The load location for configuration for pipstar.",
    ),
    "dep_template": attr.string(
        doc = """
The dep template to use for referencing the dependencies. It should have `{name}`
and `{target}` tokens that will be replaced with the normalized distribution name
and the target that we need respectively.

For example if your whl depends on `numpy` and your Python package repo is named
`pip` so that you would normally do `@pip//numpy`, then this should be: `@pip//{name}`.
""",
    ),
    "group_deps": attr.string_list(
        doc = "List of dependencies to skip in order to break the cycles within a dependency group.",
        default = [],
    ),
    "group_name": attr.string(
        doc = "Name of the group, if any.",
    ),
    "requirement": attr.string(
        mandatory = True,
        doc = "Python requirement string describing the package to make available, if 'urls' or 'whl_file' is given, then this only needs to include foo[any_extras] as a bare minimum.",
    ),
}

def _whl_deps_repo_impl(rctx):
    logger = repo_utils.logger(rctx)

    if rctx.attr.metadata_file and rctx.attr.metadata:
        logger.fail("Only one of 'metadata_file' and 'metadata' can be specified")
        return
    if not (rctx.attr.metadata_file or rctx.attr.metadata):
        logger.fail("At least one of 'metadata_file' and 'metadata' must be specified")
        return

    if rctx.attr.metadata_file:
        metadata_contents = rctx.read(rctx.attr.metadata_file)
    else:
        metadata_contents = rctx.attr.metadata

    metadata = struct(**json.decode(metadata_contents))

    build_file_contents = generate_whl_library_build_bazel(
        dep_template = rctx.attr.dep_template or "@{}{{name}}//:{{target}}".format(
            rctx.attr.repo_prefix,
        ),
        config_load = rctx.attr.config_load,
        metadata_name = metadata.name,
        metadata_version = metadata.version,
        requires_dist = metadata.requires_dist,
        group_deps = rctx.attr.group_deps,
        group_name = rctx.attr.group_name,
        repo = rctx.attr.repo or (
            str(rctx.attr.metadata_file) if rctx.attr.metadata_file else None
        ),
        extras = requirement(rctx.attr.requirement).extras,
    )
    rctx.file("BUILD.bazel", build_file_contents)

whl_deps_repo = repository_rule(
    attrs = whl_deps_attrs | {
        "metadata": attr.string(
            doc = """
The subset of the METADATA contents that is needed for generation of the dependencies.
* name: {type}`str`
* version: {type}`str`
* provides_extra: {type}`list[str]`
* requires_dist: {type}`list[str]`
""",
        ),
        "metadata_file": attr.label(doc = "An alternative way to pass {attr}`metadata` but as a file."),
        "repo": attr.label(doc = "A label at the root of the repo to get stuff from."),
    } | {
        "_rule_name": attr.string(default = "whl_deps_repo"),
    },
    doc = """
A repo rule that reuses the sources from a different place and then creates the necessary targets
so that this can be used in the repo.

Does not depend on any python.
""",
    implementation = _whl_deps_repo_impl,
    environ = [REPO_DEBUG_ENV_VAR],
)

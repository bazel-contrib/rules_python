"""Macro to generate many py_library targets for benchmarking py_wheel."""

load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("//python:py_library.bzl", "py_library")

def gen_py_libs(name, count):
    """Generate `count` py_library targets, each with a single .py file.

    Uses deeply nested paths to simulate real-world package structures.
    Longer paths amplify the cost of O(n^2) string concatenation in the
    analysis phase, making quadratic scaling easier to detect.

    Args:
        name: Base name prefix for generated targets.
        count: Number of py_library targets to generate.

    Returns:
        A list of label strings for use as py_wheel deps.
    """

    # Deep path prefix to make each _input_file_to_arg line long, simulating
    # real-world monorepo package paths. Longer per-line strings make the
    # quadratic string-concat cost dominate over linear target loading,
    # so the scaling ratio reliably distinguishes O(n) from O(n^2).
    deep_prefix = "/".join([
        "pkg_{}".format(name),
        "src",
        "python",
        "company_name_placeholder",
        "organization_unit_division",
        "engineering_team_name",
        "project_name_repository",
        "subproject_component_area",
        "internal_implementation_detail",
        "generated_sources_directory",
        "modules_directory_location",
        "feature_area_subdivision",
        "subsystem_layer_component",
        "detail_level_implementation",
        "version_specific_code_path",
        "platform_dependent_modules",
    ])

    labels = []
    for i in range(count):
        src_name = "{}_src_{}".format(name, i)
        lib_name = "{}_lib_{}".format(name, i)

        write_file(
            name = src_name,
            out = "{}/module_{}.py".format(deep_prefix, i),
            content = [
                "# Generated module {} of {}".format(i, count),
                "VALUE = {}".format(i),
                "",
            ],
        )

        py_library(
            name = lib_name,
            srcs = [src_name],
        )

        labels.append(":{}".format(lib_name))

    return labels

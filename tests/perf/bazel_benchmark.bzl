"""A rule to measure the Starlark code with Bazel itself, see the README.md."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(":workloads.bzl", "WORKLOADS")

def _bazel_benchmark_impl(ctx):
    fn = WORKLOADS[ctx.attr._workload[BuildSettingInfo].value]
    for _ in range(ctx.attr._iterations[BuildSettingInfo].value):
        fn()

    return []

bazel_benchmark = rule(
    implementation = _bazel_benchmark_impl,
    doc = "Runs the workload that is selected with the flags during the analysis.",
    attrs = {
        "_iterations": attr.label(default = ":iterations"),
        "_workload": attr.label(default = ":workload"),
    },
)

"""Aspect definition for Pyrefly static type checking."""

load("@rules_pyrefly//pyrefly:pyrefly.bzl", "pyrefly")

pyrefly_aspect = pyrefly(
    opt_in_tags = ["pyrefly"],
)

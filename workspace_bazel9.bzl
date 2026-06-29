"""Workaround for Bazel 9 duplicate name issue in Gazelle."""

def bazel_9_workaround(name = "bazel_9_workaround"):
    # Necessary so that Bazel 9 recognizes this as rules_python and doesn't try
    # to load the version Bazel itself uses by default.
    # We hide this from Gazelle's WORKSPACE parser by putting it in a macro.
    native.local_repository(
        name = "rules_python",
        path = ".",
    )

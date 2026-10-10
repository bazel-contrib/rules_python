(bootstrap) Bazel 7 native Python targets can run with both the Python and
shell bootstraps without crashing on unexpanded launcher placeholders. Their
declared import roots and repository imports are available when the launcher
falls back to executing the main file directly.

"""Private application image shared by directory and archive executables."""

PyApplicationInfo = provider(
    doc = "Private logical application files and preparation specification.",
    fields = {
        "runfiles": "Complete logical application image, without its launcher.",
        "settings": "The specification's build-time values, for entry adapters.",
        "spec": "File containing the private versioned launch specification.",
        "symlinks": "depset[ExplicitSymlink] completing the logical image.",
    },
)

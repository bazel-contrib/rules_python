"""Provider for an installed wheel directory (TreeArtifact)."""

PyInstalledWheelInfo = provider(
    doc = """
Information about an installed Python wheel TreeArtifact.

:::{versionadded} VERSION_NEXT_FEATURE
:::
""",
    fields = {
        "directory": """
:type: File
The installed wheel TreeArtifact directory containing site-packages/, data/,
bin/, and include/.
""",
        "keep_source": """
:type: bool
Whether `.py` source files are retained in `directory`.
""",
        "precompiled": """
:type: bool
Whether `.py` files in `directory` were precompiled into `.pyc` files.
""",
        "settings_key": """
:type: tuple
Tuple of install settings `(should_precompile, keep_source, invalidation_mode,
optimize_level, srcs_exclude, data_exclude, create_namespace_inits)` used to
determine whether an outer `py_wheel_library` can reuse `directory`.
""",
        "wheel": """
:type: File | None
The underlying `.whl` file (or `.whldir` directory) when the installed wheel has
no `post_install_patches`, or `None` if `post_install_patches` were applied.
""",
    },
)

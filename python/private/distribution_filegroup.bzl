"""Helper for defining distribution filegroups."""

def distribution_filegroup(name, exclude = None):
    """Defines a filegroup target for repository distribution.

    Args:
        name: The name of the filegroup target.
        exclude: Optional list of subpackage patterns to exclude from automatic
            subpackage discovery.
    """
    exclude = exclude or []
    pkg = native.package_name()
    prefix = ("//" + pkg + "/") if pkg else "//"

    srcs = native.glob(["**"])
    for subpkg in native.subpackages(
        include = ["*"],
        exclude = exclude,
        allow_empty = True,
    ):
        srcs.append(prefix + subpkg + ":distribution")

    native.filegroup(
        name = name,
        srcs = srcs,
    )

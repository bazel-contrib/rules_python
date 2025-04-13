"""A simple function to find the METADATA file and parse it"""

_NAME = "Name: "
_PROVIDES_EXTRA = "Provides-Extra: "
_REQUIRES_DIST = "Requires-Dist: "
_VERSION = "Version: "

def whl_metadata(*, install_dir, read_fn, logger):
    """Find and parse the METADATA file in the extracted whl contents dir.

    Args:
        install_dir: {type}`path` location where the wheel has been extracted.
        read_fn: the function used to read files.
        logger: the function used to log failures.

    Returns:
        A struct with parsed values:
        * `name`: {type}`str` the name of the wheel.
        * `version`: {type}`str` the version of the wheel.
        * `requires_dist`: {type}`list[str]` the list of requirements.
        * `provides_extra`: {type}`list[str]` the list of extras that this package
          provides.
    """
    metadata_file = find_whl_metadata(install_dir = install_dir, logger = logger)
    return parse_whl_metadata(read_fn(metadata_file))

def parse_whl_metadata(contents):
    """Parse .whl METADATA file

    Args:
        contents: {type}`str` the contents of the file.

    Returns:
        A struct with parsed values:
        * `name`: {type}`str` the name of the wheel.
        * `version`: {type}`str` the version of the wheel.
        * `requires_dist`: {type}`list[str]` the list of requirements.
        * `provides_extra`: {type}`list[str]` the list of extras that this package
          provides.
    """
    single_value_fields = {
        _NAME: "name",
        _VERSION: "version",
    }
    parsed = {}
    for line in contents.strip().split("\n"):
        if not line.strip():
            # Stop parsing on first empty line, which marks the end of the
            # headers containing the metadata.
            break

        found_prefix = None
        for prefix in single_value_fields:
            if line.startswith(prefix):
                found_prefix = prefix
                break

        if found_prefix:
            key = single_value_fields.pop(found_prefix)
            _, _, value = line.partition(found_prefix)
            parsed[key] = value.strip()
            continue

        if line.startswith(_REQUIRES_DIST):
            _, _, value = line.partition(_REQUIRES_DIST)
            parsed.setdefault("requires_dist", []).append(value.strip(" "))
        elif line.startswith(_PROVIDES_EXTRA):
            _, _, value = line.partition(_PROVIDES_EXTRA)
            parsed.setdefault("provides_extra", []).append(value.strip(" "))

    return struct(
        name = parsed["name"],
        version = parsed["version"],
        license = parsed.get("license"),
        requires_dist = parsed.get("requires_dist", []),
        provides_extra = parsed.get("provides_extra", []),
    )

def find_whl_metadata(*, install_dir, logger):
    """Find the whl METADATA file in the install_dir.

    Args:
        install_dir: {type}`path` location where the wheel has been extracted.
        logger: the function used to log failures.

    Returns:
        {type}`path` The path to the METADATA file.
    """
    dist_info = None
    for maybe_dist_info in install_dir.readdir():
        # first find the ".dist-info" folder
        if not (maybe_dist_info.is_dir and maybe_dist_info.basename.endswith(".dist-info")):
            continue

        dist_info = maybe_dist_info
        metadata_file = dist_info.get_child("METADATA")

        if metadata_file.exists:
            return metadata_file

        break

    if dist_info:
        logger.fail("The METADATA file for the wheel could not be found in '{}/{}'".format(install_dir.basename, dist_info.basename))
    else:
        logger.fail("The '*.dist-info' directory could not be found in '{}'".format(install_dir.basename))
    return None

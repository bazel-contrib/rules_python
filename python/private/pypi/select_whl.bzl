"Select a single wheel that fits the parameters of a target platform."

load("//python/private:version.bzl", "version")
load(":parse_whl_name.bzl", "parse_whl_name")
load(":python_tag.bzl", "PY_TAG_GENERIC", "python_tag")

def _get_priority(*, tag, values, allow_wildcard = True):
    keys = []
    for priority, wp in enumerate(values):
        head, sep, tail = wp.partition("*")
        if "*" in tail:
            fail("only a single '*' can be present in the matcher")
        if not allow_wildcard and sep:
            fail("'*' is not allowed in the matcher")

        if not sep and tag == head:
            keys.append(priority)
        elif sep and tag.startswith(head) and tag.endswith(tail):
            keys.append(priority)

    if not keys:
        return None

    return max(keys)

def _get_py_priority(*, tag, implementation, py_version):
    if tag.startswith(PY_TAG_GENERIC):
        ver_str = tag[len(PY_TAG_GENERIC):]
    elif tag.startswith(implementation):
        ver_str = tag[len(implementation):]
    else:
        return None

    # Add a 0 at the end in case it is a single digit
    ver_str = "{}.{}".format(ver_str[0], ver_str[1:] or "0")

    ver = version.parse(ver_str)
    if not version.is_compatible(py_version, ver):
        return None

    return (
        tag.startswith(implementation),
        version.key(ver),
    )

def _tag_sets(*, whls, implementation, py_version, whl_abi_tags, platforms):
    ret = {}
    for whl in whls:
        parsed = parse_whl_name(whl.filename)

        # See https://packaging.python.org/en/latest/specifications/platform-compatibility-tags/#compressed-tag-sets
        for py in parsed.python_tag.split("."):
            py = _get_py_priority(
                tag = py,
                implementation = implementation,
                py_version = py_version,
            )
            if py == None:
                ret[struct(py = py)] = whl
                continue

            for abi in parsed.abi_tag.split("."):
                abi = _get_priority(
                    tag = abi,
                    values = whl_abi_tags,
                    allow_wildcard = False,
                )
                if py == None:
                    ret[struct(py = py, abi = abi)] = whl
                    continue

                for p in parsed.platform_tag.split("."):
                    platform = _get_priority(
                        tag = p,
                        values = platforms,
                    )

                    ret[struct(py = py, abi = abi, platform = platform)] = whl

    return ret

def select_whl(*, whls, python_version, platforms, whl_abi_tags, implementation_name = "cpython", limit = 1, logger = None):
    """Select a whl that is the most suitable for the given platform.

    Args:
        whls: {type}`list[struct]` a list of candidates which have a `filename`
            attribute containing the `whl` filename.
        python_version: {type}`str` the target python version.
        platforms: {type}`list[str]` the target platform identifiers that may contain
            a single `*` character.
        implementation_name: {type}`str` the `implementation_name` from the target_platform env.
        whl_abi_tags: {type}`str` the ABIs that the target_platform is compatible with.
        limit: {type}`int` number of wheels to return. Defaults to 1.
        logger: {type}`struct` the logger instance.

    Returns:
        {type}`list[struct] | struct | None`, a single struct from the `whls` input
            argument or `None` if a match is not found. If the `limit` is greater than
            one, then we will return a list.
    """
    py_version = version.parse(python_version, strict = True)
    candidates = {}
    implementation = python_tag(implementation_name)

    for priority, whl in _tag_sets(
        whls = whls,
        implementation = implementation,
        py_version = py_version,
        whl_abi_tags = whl_abi_tags,
        platforms = platforms,
    ).items():
        if priority.py == None:
            if logger:
                logger.debug(lambda: "The python_tag in '{}' does not match implementation or version: {} {}".format(
                    whl.filename,
                    implementation,
                    py_version.string,
                ))
            continue
        elif priority.abi == None:
            if logger:
                logger.debug(lambda: "The abi_tag in '{}' does not match given list: {}".format(
                    whl.filename,
                    whl_abi_tags,
                ))
            continue
        elif priority.platform == None:
            if logger:
                logger.debug(lambda: "The platform_tag in '{}' does not match given list: {}".format(
                    whl.filename,
                    platforms,
                ))
            continue

        candidates.setdefault((
            priority.platform,  # Prefer platform wheels
            priority.py,  # Then prefer implementation/python version
            priority.abi,  # Then prefer more specific ABI wheels
        ), whl)

    if not candidates:
        return None

    res = [i[1] for i in sorted(candidates.items())]
    if logger:
        logger.debug(lambda: "Sorted candidates:\n{}".format(
            "\n".join([c.filename for c in res]),
        ))

    return res[-1] if limit == 1 else res[-limit:]

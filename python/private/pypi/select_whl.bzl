"Select a single wheel that fits the parameters of a target platform."

load("//python/private:version.bzl", "version")
load(":parse_whl_name.bzl", "parse_whl_name")
load(":python_tag.bzl", "PY_TAG_GENERIC", "python_tag")

def _get_priority(*, tags, values, allow_wildcard = True):
    keys = []
    for priority, wp in enumerate(values):
        for tag in tags.split("."):
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

def _get_py_priority(*, tags, implementation, py_version):
    keys = []
    for tag in tags.split("."):
        if tag.startswith(PY_TAG_GENERIC):
            ver_str = tag[len(PY_TAG_GENERIC):]
        elif tag.startswith(implementation):
            ver_str = tag[len(implementation):]
        else:
            continue

        # Add a 0 at the end in case it is a single digit
        ver_str = "{}.{}".format(ver_str[0], ver_str[1:] or "0")

        ver = version.parse(ver_str)
        if not version.is_compatible(py_version, ver):
            continue

        keys.append((
            tag.startswith(implementation),
            version.key(ver),
            # Prefer shorter py_tags, which will yield more specialized matches,
            # like preferring py3 over py2.py3
            -len(tags),
        ))

    if not keys:
        return None

    return max(keys)

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

    for whl in whls:
        parsed = parse_whl_name(whl.filename)

        if parsed.python_tag.startswith(PY_TAG_GENERIC):
            pass
        elif not parsed.python_tag.startswith(implementation):
            if logger:
                logger.debug(lambda: "Discarding the wheel because the implementation '{}' is not compatible with target implementation '{}'".format(
                    parsed.python_tag,
                    implementation,
                ))
            continue

        py_priority = _get_py_priority(
            tags = parsed.python_tag,
            implementation = implementation,
            py_version = py_version,
        )
        if py_priority == None:
            if logger:
                logger.debug(lambda: "The py_tag '{}' does not match implementation version: {} {}".format(
                    parsed.py_tag,
                    implementation,
                    py_version.string,
                ))
            continue

        abi_priority = _get_priority(
            tags = parsed.abi_tag,
            values = whl_abi_tags,
            allow_wildcard = False,
        )
        if abi_priority == None:
            if logger:
                logger.debug(lambda: "The abi '{}' does not match given list: {}".format(
                    parsed.abi_tag,
                    whl_abi_tags,
                ))
            continue

        platform_priority = _get_priority(
            tags = parsed.platform_tag,
            values = platforms,
        )
        if platform_priority == None:
            if logger:
                logger.debug(lambda: "The platform_tag '{}' does not match given list: {}".format(
                    parsed.platform_tag,
                    platforms,
                ))
            continue

        key = (
            # Ensure that we chose the highest compatible version
            py_priority,
            platform_priority,
            abi_priority,
        )
        candidates.setdefault(key, whl)

    if not candidates:
        return None

    res = [i[1] for i in sorted(candidates.items())]
    if logger:
        logger.debug(lambda: "Sorted candidates:\n{}".format(
            "\n".join([c.filename for c in res]),
        ))

    return res[-1] if limit == 1 else res[-limit:]

"Select a single wheel that fits the parameters of a target platform."

load("//python/private:version.bzl", "version")
load(":parse_whl_name.bzl", "parse_whl_name")
load(":python_tag.bzl", "PY_TAG_GENERIC", "python_tag")

_ANDROID = "android"
_IOS = "ios"
_MANYLINUX = "manylinux"
_MACOSX = "macosx"
_MUSLLINUX = "musllinux"

def _value_priority(*, tag, values):
    keys = []
    for priority, wp in enumerate(values):
        if tag == wp:
            keys.append(priority)

    return max(keys) if keys else None

def _platform_tag_priority(*, tag, values):
    # Implements matching platform tag
    # https://packaging.python.org/en/latest/specifications/platform-compatibility-tags/

    if not (
        tag.startswith(_ANDROID) or
        tag.startswith(_IOS) or
        tag.startswith(_MACOSX) or
        tag.startswith(_MANYLINUX) or
        tag.startswith(_MUSLLINUX)
    ):
        res = _value_priority(tag = tag, values = values)
        if res == None:
            return res

        return (res, (0, 0))

    plat, _, tail = tag.partition("_")
    major, _, tail = tail.partition("_")
    if not plat.startswith(_ANDROID):
        minor, _, arch = tail.partition("_")
    else:
        minor = "0"
        arch = tail
    version = (int(major), int(minor))

    keys = []
    for priority, wp in enumerate(values):
        want_plat, sep, tail = wp.partition("_")
        if not sep:
            continue

        if want_plat != plat:
            continue

        want_major, _, tail = tail.partition("_")
        if want_major == "*":
            want_major = ""
            want_minor = ""
            want_arch = tail
        elif plat.startswith(_ANDROID):
            want_minor = "0"
            want_arch = tail
        else:
            want_minor, _, want_arch = tail.partition("_")

        if want_arch != arch:
            continue

        want_version = (int(want_major), int(want_minor)) if want_major else None
        if not want_version or version <= want_version:
            keys.append((priority, version))

    return max(keys) if keys else None

def _python_tag_priority(*, tag, implementation, py_version):
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

def _candidates_by_priority(
        *,
        whls,
        implementation_name,
        python_version,
        whl_abi_tags,
        whl_platform_tags,
        logger):
    """Calculate the priority of each wheel

    Returns:
        A dictionary where keys are priority tuples which allows us to sort and pick the
        last item.
    """
    py_version = version.parse(python_version, strict = True)
    implementation = python_tag(implementation_name)

    ret = {}
    for whl in whls:
        parsed = parse_whl_name(whl.filename)
        priority = None

        # See https://packaging.python.org/en/latest/specifications/platform-compatibility-tags/#compressed-tag-sets
        for platform in parsed.platform_tag.split("."):
            platform = _platform_tag_priority(tag = platform, values = whl_platform_tags)
            if platform == None:
                if logger:
                    logger.debug(lambda: "The platform_tag in '{}' does not match given list: {}".format(
                        whl.filename,
                        whl_platform_tags,
                    ))
                continue

            for py in parsed.python_tag.split("."):
                py = _python_tag_priority(
                    tag = py,
                    implementation = implementation,
                    py_version = py_version,
                )
                if py == None:
                    if logger:
                        logger.debug(lambda: "The python_tag in '{}' does not match implementation or version: {} {}".format(
                            whl.filename,
                            implementation,
                            py_version.string,
                        ))
                    continue

                for abi in parsed.abi_tag.split("."):
                    abi = _value_priority(
                        tag = abi,
                        values = whl_abi_tags,
                    )
                    if abi == None:
                        if logger:
                            logger.debug(lambda: "The abi_tag in '{}' does not match given list: {}".format(
                                whl.filename,
                                whl_abi_tags,
                            ))
                        continue

                    # 1. Prefer platform wheels
                    # 2. Then prefer implementation/python version
                    # 3. Then prefer more specific ABI wheels
                    candidate = (platform, py, abi)
                    priority = priority or candidate
                    if candidate > priority:
                        priority = candidate

        if priority == None:
            if logger:
                logger.debug(lambda: "The whl '{}' is incompatible".format(
                    whl.filename,
                ))
            continue

        ret[priority] = whl

    return ret

def select_whl(
        *,
        whls,
        python_version,
        whl_platform_tags,
        whl_abi_tags,
        implementation_name = "cpython",
        limit = 1,
        logger = None):
    """Select a whl that is the most suitable for the given platform.

    Args:
        whls: {type}`list[struct]` a list of candidates which have a `filename`
            attribute containing the `whl` filename.
        python_version: {type}`str` the target python version.
        implementation_name: {type}`str` the `implementation_name` from the target_platform env.
        whl_abi_tags: {type}`list[str]` The whl abi tags to select from. The preference is
            for wheels that have ABI values appearing later in the `whl_abi_tags` list.
        whl_platform_tags: {type}`list[str]` The whl platform tags to select from.
            The platform tag may contain `*` and this means that if the platform tag is
            versioned (e.g. `manylinux`), then we will select the highest available
            platform version, e.g. if `manylinux_2_17` and `manylinux_2_5` wheels are both
            compatible, we will select `manylinux_2_17`. Otherwise for versioned platform
            tags we select the highest *compatible* version, e.g. if `manylinux_2_6`
            support is requested, then we would select `manylinux_2_5` in the previous
            example. This allows us to pass the same filtering parameters when selecting
            all of the whl dependencies irrespective of what actual platform tags they
            contain.
        limit: {type}`int` number of wheels to return. Defaults to 1.
        logger: {type}`struct` the logger instance.

    Returns:
        {type}`list[struct] | struct | None`, a single struct from the `whls` input
            argument or `None` if a match is not found. If the `limit` is greater than
            one, then we will return a list.
    """
    candidates = _candidates_by_priority(
        whls = whls,
        implementation_name = implementation_name,
        python_version = python_version,
        whl_abi_tags = whl_abi_tags,
        whl_platform_tags = whl_platform_tags,
        logger = logger,
    )

    if not candidates:
        return None

    res = [i[1] for i in sorted(candidates.items())]
    if logger:
        logger.debug(lambda: "Sorted candidates:\n{}".format(
            "\n".join([c.filename for c in res]),
        ))

    return res[-1] if limit == 1 else res[-limit:]

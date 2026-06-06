"""Helper functions to parse python-build-standalone manifests."""

def parse_filename(filename):
    """Parses a python-build-standalone filename (or URL) into its components.

    See https://gregoryszorc.com/docs/python-build-standalone/main/running.html

    Example: cpython-3.10.20+20260414-x86_64_v2-unknown-linux-musl-lto-full.tar.zst

    Args:
      filename: The filename or URL of the python-build-standalone release asset.

    Returns:
      A dictionary of parsed components if parsed successfully, else None.
    """
    basename = filename.rpartition("/")[-1]
    if basename.endswith(".tar.zst"):
        name = basename.removesuffix(".tar.zst")
    elif basename.endswith(".tar.gz"):
        name = basename.removesuffix(".tar.gz")
    else:
        return None

    if not name.startswith("cpython-"):
        return None
    name = name.removeprefix("cpython-")

    left, plus, tail = name.partition("+")
    if plus:
        python_version = left
        build_version, sep, rest = tail.partition("-")
        if not sep:
            return None
    else:
        python_version, sep, rest = left.partition("-")
        if not sep:
            return None
        build_version = ""

    arch, sep, rest = rest.partition("-")
    if not sep:
        return None

    microarch = ""
    arch_base, sep_v, microarch_num = arch.partition("_v")
    if sep_v:
        arch = arch_base
        microarch = "v" + microarch_num

    vendor, sep, rest = rest.partition("-")
    if not sep:
        return None

    os, sep, rest = rest.partition("-")
    if not sep:
        return None

    libc = ""
    next_part, _, remaining = rest.partition("-")
    if os == "linux" and next_part in ["gnu", "musl"]:
        libc = next_part
        flavor = remaining
    elif os == "windows" and next_part == "msvc":
        libc = next_part
        flavor = remaining
    else:
        libc = ""
        flavor = rest

    freethreaded = False
    if flavor.startswith("freethreaded+"):
        freethreaded = True
        flavor = flavor.removeprefix("freethreaded+")
    elif flavor.startswith("freethreaded-"):
        freethreaded = True
        flavor = flavor.removeprefix("freethreaded-")
    elif flavor == "freethreaded":
        freethreaded = True
        flavor = ""

    archive_flavor = ""
    if flavor.endswith("-full"):
        archive_flavor = "full"
        flavor = flavor.removesuffix("-full")
    elif flavor == "full":
        archive_flavor = "full"
        flavor = ""
    elif flavor.endswith("-install_only_stripped"):
        archive_flavor = "install_only_stripped"
        flavor = flavor.removesuffix("-install_only_stripped")
    elif flavor == "install_only_stripped":
        archive_flavor = "install_only_stripped"
        flavor = ""
    elif flavor.endswith("-install_only"):
        archive_flavor = "install_only"
        flavor = flavor.removesuffix("-install_only")
    elif flavor == "install_only":
        archive_flavor = "install_only"
        flavor = ""

    return {
        "arch": arch,
        "archive_flavor": archive_flavor,
        "build_version": build_version,
        "flavor": flavor,
        "freethreaded": freethreaded,
        "libc": libc,
        "location": filename,
        "microarch": microarch,
        "os": os,
        "python_version": python_version,
        "vendor": vendor,
    }

def parse_sha_manifest(content):
    """Parses the SHA256SUMS file content into a list of structs.

    Args:
      content: The raw content of the manifest file.

    Returns:
      A list of structs capturing the parsed components of each valid entry.
      Each struct contains the following fields:
        - arch: CPU architecture (e.g., "x86_64").
        - archive_flavor: Release asset archive type (e.g., "full", "install_only").
        - build_version: Standalone release date (e.g., "20260414").
        - location: Full package filename or URL (e.g., "cpython-3.11.15..." or "https://...").
        - flavor: Build configuration flavor (e.g., "install_only").
        - freethreaded: Whether the build is free-threaded (boolean).
        - libc: C library type (e.g., "gnu", "musl", "msvc", or "").
        - microarch: Microarchitecture level (e.g., "v2", "v3", or "").
        - os: Operating system (e.g., "linux", "darwin", "windows").
        - python_version: Python semver version (e.g., "3.11.15").
        - sha256: SHA256 integrity hash of the release asset.
        - vendor: Platform vendor (e.g., "unknown", "apple").
    """
    results = []
    for line in content.split("\n"):
        line = line.strip()
        if not line:
            continue
        parts = [p for p in line.split(" ") if p]
        if len(parts) != 2:
            continue
        sha256, filename = parts

        parsed = parse_filename(filename)
        if parsed:
            results.append(struct(
                sha256 = sha256,
                **parsed
            ))
    return results

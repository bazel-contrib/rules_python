"""Convert a parsed uv.lock to requirements.txt format."""

def uv_lock_extras_map(uv_lock):
    """Compute extras for each package from uv.lock data.

    Args:
      uv_lock: a decoded JSON struct from a uv.lock file.

    Returns:
      A dict of {package_name: [extra1, extra2, ...]} for packages with extras.
    """
    extras_map = {}
    for pkg in uv_lock.get("package", []):
        pkg_name = pkg.get("name", "")

        for extra in pkg.get("provides-extras", pkg.get("extras", [])):
            _add_extras(extras_map, pkg_name, [extra])

        opt_deps = pkg.get("optional-dependencies", {})
        if opt_deps:
            _add_extras(extras_map, pkg_name, _sorted(opt_deps.keys()))

        deps = pkg.get("dependencies", [])
        for dep in deps:
            dep_name = dep.get("name", "")
            dep_extras_raw = dep.get("extra", [])
            dep_extras = [dep_extras_raw] if type(dep_extras_raw) == "string" else dep_extras_raw
            if dep_extras and dep_name != pkg_name:
                _add_extras(extras_map, dep_name, dep_extras)

        metadata = pkg.get("metadata", {})
        for rd in metadata.get("requires-dist", []):
            rd_name = rd.get("name", "")
            rd_extras_raw = rd.get("extras", [])
            rd_extras = [rd_extras_raw] if type(rd_extras_raw) == "string" else rd_extras_raw
            if rd_extras and rd_name != pkg_name:
                _add_extras(extras_map, rd_name, rd_extras)

    return extras_map

def uv_lock_to_requirements(uv_lock):
    """Convert a parsed uv.lock JSON struct to a requirements.txt formatted string.

    Args:
      uv_lock: a decoded JSON struct from a uv.lock file.

    Returns:
      A requirements.txt formatted string.
    """
    packages = uv_lock.get("package", [])
    extras_map = uv_lock_extras_map(uv_lock)

    dependents = {}
    for pkg in packages:
        pkg_name = pkg.get("name", "")
        deps = pkg.get("dependencies", [])
        for dep in deps:
            dep_name = dep.get("name", "")
            if dep_name != pkg_name:
                _add_dependent(dependents, dep_name, pkg_name)
        opt_deps = pkg.get("optional-dependencies", {})
        for _extra, deps in opt_deps.items():
            for dep in deps:
                dep_name = dep.get("name", "")
                if dep_name != pkg_name:
                    _add_dependent(dependents, dep_name, pkg_name)

    lines = []
    for pkg in packages:
        source = pkg.get("source", {})
        if not source.get("registry"):
            continue

        pkg_name = pkg.get("name", "")
        version = pkg.get("version", "")

        markers = pkg.get("resolution-markers", [])
        hashes = _collect_hashes(pkg)

        pkg_extras = extras_map.get(pkg_name, [])
        if pkg_extras:
            req = "{}[{}]=={}".format(pkg_name, ",".join(pkg_extras), version)
        else:
            req = "{}=={}".format(pkg_name, version)
        if markers:
            req += " ; " + " or ".join(markers)

        if hashes:
            req += " \\"
        lines.append(req)

        _emit_hashes(lines, hashes)

        dep_vias = _sorted(dependents.get(pkg_name, []))
        if dep_vias:
            if len(dep_vias) == 1:
                lines.append("    # via " + dep_vias[0])
            else:
                lines.append("    # via")
                for via in dep_vias:
                    lines.append("    #   " + via)

        lines.append("")

    return "\n".join(lines)

def _add_dependent(dependents, dep_name, dependent_name):
    if dep_name not in dependents:
        dependents[dep_name] = []
    if dependent_name not in dependents[dep_name]:
        dependents[dep_name].append(dependent_name)

def _add_extras(extras_map, pkg_name, extras):
    existing = extras_map.get(pkg_name, [])
    for extra in extras:
        if extra not in existing:
            existing.append(extra)
    extras_map[pkg_name] = _sorted(existing)

def _collect_hashes(pkg):
    hashes = []
    for wheel in pkg.get("wheels", []):
        whash = wheel.get("hash", "")
        if whash.startswith("sha256:"):
            hashes.append(whash[len("sha256:"):])
    sdist = pkg.get("sdist")
    if sdist:
        shash = sdist.get("hash", "")
        if shash.startswith("sha256:"):
            hashes.append(shash[len("sha256:"):])
    return _sorted(hashes)

def _sorted(items):
    return sorted(items)

def _emit_hashes(lines, hashes):
    for i, h in enumerate(hashes):
        suffix = " \\" if i < len(hashes) - 1 else ""
        lines.append("    --hash=sha256:{}{}".format(h, suffix))

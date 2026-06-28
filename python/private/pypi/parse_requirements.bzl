# Copyright 2024 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Requirements parsing for whl_library creation.

Use cases that the code needs to cover:
* A single requirements_lock file that is used for the host platform.
* Per-OS requirements_lock files that are used for the host platform.
* A target platform specific requirements_lock that is used with extra
  pip arguments with --platform, etc and download_only = True.

In the last case only a single `requirements_lock` file is allowed, in all
other cases we assume that there may be a desire to resolve the requirements
file for the host platform to be backwards compatible with the legacy
behavior.
"""

load("//python/private:normalize_name.bzl", "normalize_name")
load("//python/private:repo_utils.bzl", "repo_utils")
load("//python/uv/private:uv_lock_to_requirements.bzl", "uv_lock_extras_map")  # buildifier: disable=bzl-visibility
load(":argparse.bzl", "argparse")
load(":index_sources.bzl", "index_sources")
load(":parse_requirements_txt.bzl", "parse_requirements_txt")
load(":pep508_evaluate.bzl", "evaluate")
load(":pep508_requirement.bzl", "requirement")
load(":select_whl.bzl", "select_whl")

def parse_requirements(
        ctx,
        *,
        requirements_by_platform = {},
        extra_pip_args = [],
        platforms,
        get_index_urls = None,
        extract_url_srcs = True,
        uv_lock = None,
        toml_decode = None,
        logger):
    """Get the requirements with platforms that the requirements apply to.

    Args:
        ctx: A context that has .read function that would read contents from a label.
        platforms: The target platform descriptions. Cannot be empty and needs to have
            at least the host platform and the definitions.
        requirements_by_platform (label_keyed_string_dict): a way to have
            different package versions (or different packages) for different
            os, arch combinations.
        extra_pip_args (string list): Extra pip arguments to perform extra validations and to
            be joined with args found in files.
        get_index_urls: Callable[[ctx, dict[str, list[str]]], dict], a callable to get all
            of the distribution URLs from a PyPI index. Accepts ctx and
            distribution names to query.
        extract_url_srcs: A boolean to enable extracting URLs from requirement
            lines to enable using bazel downloader.
        uv_lock: {type}`str | None` an optional label/file path to the uv.lock
            file. The ctx.read function will be used to read the contents.
            If provided, the function will use the uv.lock file as the primary
            source for package metadata and perform a consistency check against
            requirements files if both are provided.
        toml_decode: {type}`callable | None` A function to decode TOML
            content (e.g. `toml.decode`). Required when `uv_lock` is provided.
        logger: repo_utils.logger, a simple struct to log diagnostic messages.

    Returns:
        {type}`list[struct]` where each struct contains the following attributes:
         * `name`: {type}`str` The normalized distribution name.
         * `is_exposed`: {type}`bool` `True` if the package should be exposed via the hub
           repository.
         * `is_multiple_versions`: {type}`bool` `True` if multiple versions have been
           specified for this package.
         * `index_url`: {type}`str` The index URL used to download the package.
         * `srcs`: {type}`list[struct]` A list of per-distribution source entries, each
           containing: `distribution`, `extra_pip_args`, `requirement_line`,
           `target_platforms`, `filename`, `sha256`, `url`, `yanked`.
    """
    if uv_lock and toml_decode:
        uv_lock = toml_decode(ctx.read(uv_lock))
        return _parse_requirements_with_uv_lock(
            ctx = ctx,
            requirements_by_platform = requirements_by_platform,
            extra_pip_args = extra_pip_args,
            platforms = platforms,
            get_index_urls = get_index_urls,
            extract_url_srcs = extract_url_srcs,
            uv_lock = uv_lock,
            logger = logger,
        )

    return _parse_requirements_from_req_files(
        ctx = ctx,
        requirements_by_platform = requirements_by_platform,
        extra_pip_args = extra_pip_args,
        platforms = platforms,
        get_index_urls = get_index_urls,
        extract_url_srcs = extract_url_srcs,
        logger = logger,
    )

def _get_all_platforms(requirements_by_platform):
    """Get the set of all platform names from requirements_by_platform."""
    all_platforms = {}
    for plats in requirements_by_platform.values():
        for p in plats:
            all_platforms[p] = None
    return sorted(all_platforms)

def _parse_requirements_with_uv_lock(
        ctx,
        *,
        requirements_by_platform,
        extra_pip_args,
        platforms,
        get_index_urls,
        extract_url_srcs,
        uv_lock,
        logger):
    """Parse requirements using uv.lock as the primary source."""
    if uv_lock:
        return _parse_uv_lock_json(
            uv_lock = uv_lock,
            all_platforms = _get_all_platforms(requirements_by_platform) if requirements_by_platform else sorted(platforms.keys()),
            platforms = platforms,
            extra_pip_args = extra_pip_args,
            logger = logger,
        )

    return _parse_requirements_from_req_files(
        ctx = ctx,
        requirements_by_platform = requirements_by_platform,
        extra_pip_args = extra_pip_args,
        platforms = platforms,
        get_index_urls = get_index_urls,
        extract_url_srcs = extract_url_srcs,
        logger = logger,
    )

def _parse_uv_lock_json(uv_lock, all_platforms, logger, extra_pip_args = None, platforms = {}):
    """Parse uv.lock JSON and build the same return structs as parse_requirements.

    Args:
        uv_lock: {type}`dict` The decoded uv.lock contents.
        all_platforms: {type}`list[str]` The list of all platform names.
        logger: {type}`struct` A logger for diagnostic messages.
        extra_pip_args: {type}`list[str] | None` Extra pip arguments to pass through.
        platforms: {type}`dict[str, struct]` A dict of platform name to platform info
            (containing `.env` with PEP 508 marker environment).

    Returns:
        {type}`list[struct]` The same format as {func}`parse_requirements`.
    """
    extras_map = uv_lock_extras_map(uv_lock)

    uv_packages = {}

    if not platforms:
        fail("BUG: platforms must be configured")

    for pkg in uv_lock["package"]:
        name = pkg["name"]
        version = pkg["version"]
        norm_name = normalize_name(name)
        entry = uv_packages.setdefault(norm_name, {
            "distribution": name,
            "resolved_srcs": [],
            "versions": {},
        })
        entry["versions"][version] = None

        pkg_extras = sorted(extras_map.get(name, []))
        extra_str = "[{}]".format(",".join(pkg_extras)) if pkg_extras else ""

        markers = pkg.get("resolution-markers", [])
        if markers:
            marker_expr = " or ".join(markers)
            pkg_platforms = [
                p
                for p in all_platforms
                if evaluate(marker_expr, env = platforms[p].env)
            ]
        else:
            pkg_platforms = list(all_platforms)

        # Prepare candidates
        candidates = []
        for wheel in pkg.get("wheels", []):
            url = wheel["url"]
            _, _, filename = url.rpartition("/")
            sha256 = wheel.get("hash", "").replace("sha256:", "")
            candidates.append(struct(
                filename = filename,
                url = url,
                sha256 = sha256,
                kind = "wheel",
            ))

        sdist_struct = None
        sdist = pkg.get("sdist", None)
        if sdist:
            url = sdist["url"]
            _, _, filename = url.rpartition("/")
            sha256 = sdist.get("hash", "").replace("sha256:", "")
            sdist_struct = struct(
                filename = filename,
                url = url,
                sha256 = sha256,
                kind = "sdist",
            )

        git_struct = None
        if pkg.get("source", {}).get("git"):
            url = pkg["source"]["git"]
            _, _, filename = url.rpartition("/")
            git_struct = struct(
                filename = filename,
                url = url,
                sha256 = "",
                kind = "git",
                source = pkg["source"],
            )

        plat_to_src = {}
        for p in pkg_platforms:
            platform = platforms.get(p)
            if not platform:
                continue

            best_wheel = None
            if candidates:
                best_wheel = select_whl(
                    whls = candidates,
                    python_version = platform.env.get("python_full_version", "3"),
                    whl_platform_tags = platform.whl_platform_tags,
                    whl_abi_tags = platform.whl_abi_tags,
                    implementation_name = platform.env.get("implementation_name", "cpython"),
                    limit = 1,
                    logger = logger,
                )

            if best_wheel:
                plat_to_src[p] = best_wheel
            elif sdist_struct:
                plat_to_src[p] = sdist_struct
            elif git_struct:
                plat_to_src[p] = git_struct

        # Group platforms by resolved source
        src_to_plats = {}
        for p, src in plat_to_src.items():
            key = src.filename + src.sha256
            src_to_plats.setdefault(key, struct(src = src, plats = [])).plats.append(p)

        # Build resolved_srcs
        for key, val in src_to_plats.items():
            src = val.src
            plats = sorted(val.plats)
            requirement_line = "{name}{extras}=={version}".format(
                name = name,
                extras = extra_str,
                version = version,
            )
            entry["resolved_srcs"].append(struct(
                distribution = name,
                extra_pip_args = extra_pip_args or [],
                requirement_line = requirement_line,
                target_platforms = plats,
                filename = src.filename,
                sha256 = src.sha256,
                url = src.url,
                yanked = None,
            ))

    ret = []
    for norm_name, info in sorted(uv_packages.items()):
        versions = sorted(info["versions"].keys())
        item = struct(
            name = norm_name,
            is_exposed = True,
            is_multiple_versions = len(versions) > 1,
            index_url = "",
            srcs = info["resolved_srcs"],
        )
        ret.append(item)

    logger.debug(lambda: "Parsed {} packages from uv.lock".format(len(ret)))
    return ret

def _parse_requirements_from_req_files(
        ctx,
        *,
        requirements_by_platform,
        extra_pip_args,
        platforms,
        get_index_urls,
        extract_url_srcs,
        logger):
    """Parse requirements from requirements.txt files (existing behavior)."""
    options = {}
    requirements = {}
    all_files_parsed = {}
    index_url = None
    extra_index_urls = []
    for file, plats in requirements_by_platform.items():
        logger.trace(lambda: "Using {} for {}".format(file, plats))
        contents = ctx.read(file)

        parse_result = parse_requirements_txt(contents)

        if file not in all_files_parsed:
            all_files_parsed[file] = parse_result.requirements

        tokenized_options = []
        for opt in parse_result.options:
            for p in opt.split(" "):
                tokenized_options.append(p)

        pip_args = tokenized_options + extra_pip_args

        # Parse the index URL from the requirement files once per file
        index_url = argparse.index_url(pip_args, index_url)
        extra_index_urls = argparse.extra_index_url(pip_args, [])
        if argparse.platform(pip_args, []):
            # No use of downloader if the user specifies "--platform" pip arg. This means that
            # they intend to use pip to download the wheels
            #
            # TODO @aignas 2026-04-11: consider removing this line in the next major release
            # (3.0).
            get_index_urls = None

        # Pre-parse requirements once per file to avoid redundant parsing in loops
        parsed_reqs = [(entry, requirement(entry[1])) for entry in parse_result.requirements]

        for plat in plats:
            plat_env = platforms.get(plat)

            requirements[plat] = [
                entry
                for entry, req in parsed_reqs
                if not req.marker or (plat_env and evaluate(req.marker, env = plat_env.env))
            ]

            options[plat] = pip_args

            index_url = argparse.index_url(pip_args, index_url)
            extra_index_urls = argparse.extra_index_url(pip_args, [])
            platform = argparse.platform(pip_args, [])
            if platform:
                get_index_urls = None

    reqs_by_name = {}
    requirements_by_platform = {}
    for plat, parse_results in requirements.items():
        requirements_dict = {}
        for entry in sorted(
            parse_results,
            key = lambda x: (len(x[1].partition("==")[0]), x),
        ):
            req_line = entry[1]
            req = requirement(req_line)

            requirements_dict[req.name] = entry

        extra_pip_args_for_plat = options[plat]

        for distribution, requirement_line in requirements_dict.values():
            for_whl = reqs_by_name.setdefault(
                normalize_name(distribution),
                {},
            )

            for_req = for_whl.setdefault(
                (requirement_line, ",".join(extra_pip_args_for_plat)),
                struct(
                    distribution = distribution,
                    srcs = index_sources(requirement_line),
                    requirement_line = requirement_line,
                    target_platforms = [],
                    extra_pip_args = extra_pip_args_for_plat,
                ),
            )
            for_req.target_platforms.append(plat)

    index_urls = {}
    if get_index_urls:
        distributions = {}
        for entries in all_files_parsed.values():
            for entry in entries:
                name, req_line = entry
                srcs = index_sources(req_line)
                if srcs.url:
                    continue
                versions = distributions.setdefault(normalize_name(name), {})
                versions[srcs.version] = None

        distributions = {k: sorted(v.keys()) for k, v in distributions.items()}

        index_urls = get_index_urls(
            ctx,
            distributions,
            index_url = index_url,
            extra_index_urls = extra_index_urls,
        )

    ret = []
    for name, reqs in sorted(reqs_by_name.items()):
        requirement_target_platforms = {}
        for r in reqs.values():
            for p in r.target_platforms:
                requirement_target_platforms[p] = None

        pkg_sources = index_urls.get(name)
        package_srcs = _package_srcs(
            name = name,
            reqs = reqs,
            pkg_sources = pkg_sources,
            platforms = platforms,
            extract_url_srcs = extract_url_srcs,
            logger = logger,
        )

        item = struct(
            name = normalize_name(name),
            is_exposed = len(requirement_target_platforms) == len(requirements),
            is_multiple_versions = len(reqs.values()) > 1,
            index_url = pkg_sources.index_url if pkg_sources else "",
            srcs = package_srcs,
        )
        ret.append(item)
        if not item.is_exposed and logger:
            logger.trace(lambda: "Package '{}' will not be exposed because it is only present on a subset of platforms: {} out of {}".format(
                name,
                sorted(requirement_target_platforms),
                sorted(requirements),
            ))

    logger.debug(lambda: "Will configure whl repos: {}".format([w.name for w in ret]))

    return ret

def _package_srcs(
        *,
        name,
        reqs,
        pkg_sources,
        platforms,
        logger,
        extract_url_srcs):
    """A function to return sources for a particular package."""
    srcs = {}
    for r in sorted(reqs.values(), key = lambda r: r.requirement_line):
        extra_pip_args = tuple(r.extra_pip_args)

        for target_platform in r.target_platforms:
            if platforms and target_platform not in platforms:
                fail("The target platform '{}' could not be found in {}".format(
                    target_platform,
                    platforms.keys(),
                ))

            dist, can_fallback = _add_dists(
                requirement = r,
                target_platform = platforms.get(target_platform),
                index_urls = pkg_sources,
                logger = logger,
            )
            logger.debug(lambda: "The whl dist is: {}".format(dist.filename if dist else dist))

            if extract_url_srcs and dist:
                req_line = r.srcs.requirement
            elif can_fallback or (not extract_url_srcs and dist):
                dist = struct(
                    url = "",
                    filename = "",
                    sha256 = "",
                    yanked = None,
                )
                req_line = r.srcs.requirement_line
            else:
                continue

            key = (
                dist.filename,
                req_line,
                extra_pip_args,
            )
            entry = srcs.setdefault(
                key,
                struct(
                    distribution = name,
                    extra_pip_args = r.extra_pip_args,
                    requirement_line = req_line,
                    target_platforms = [],
                    filename = dist.filename,
                    sha256 = dist.sha256,
                    url = dist.url,
                    yanked = dist.yanked,
                ),
            )

            if target_platform not in entry.target_platforms:
                entry.target_platforms.append(target_platform)

    return srcs.values()

def select_requirement(requirements, *, platform):
    """A simple function to get a requirement for a particular platform.

    Only used in WORKSPACE.

    Args:
        requirements (list[struct]): The list of requirements as returned by
            the `parse_requirements` function above.
        platform (str or None): The host platform. Usually an output of the
            `host_platform` function. If None, then this function will return
            the first requirement it finds.

    Returns:
        None if not found or a struct returned as one of the values in the
        parse_requirements function. The requirement that should be downloaded
        by the host platform will be returned.
    """
    maybe_requirement = [
        req
        for req in requirements
        if not platform or [p for p in req.target_platforms if p.endswith(platform)]
    ]
    if not maybe_requirement:
        # Sometimes the package is not present for host platform if there
        # are whls specified only in particular requirements files, in that
        # case just continue, however, if the download_only flag is set up,
        # then the user can also specify the target platform of the wheel
        # packages they want to download, in that case there will be always
        # a requirement here, so we will not be in this code branch.
        return None

    return maybe_requirement[0]

def host_platform(ctx):
    """Return a string representation of the repository OS.

    Only used in WORKSPACE.

    Args:
        ctx (struct): The `module_ctx` or `repository_ctx` attribute.

    Returns:
        The string representation of the platform that we can later used in the `pip`
        machinery.
    """
    return "{}_{}".format(
        repo_utils.get_platforms_os_name(ctx),
        repo_utils.get_platforms_cpu_name(ctx),
    )

def _add_dists(*, requirement, index_urls, target_platform, logger = None):
    """Populate dists based on the information from the PyPI index.

    This function will modify the given requirements_by_platform data structure.

    Args:
        requirement: The result of parse_requirements function.
        index_urls: The result of simpleapi_download.
        target_platform: The target_platform information.
        logger: A logger for printing diagnostic info.

    Returns:
        (dist, can_fallback_to_pip): a struct with distribution details and how to fetch
        it and a boolean flag to tell the other layers if we should add an entry to
        fallback for pip if there are no supported whls found - if there is an sdist, we
        can attempt the fallback, otherwise better to not, because the pip command will
        fail and the error message will be confusing. What is more that would lead to
        breakage of the bazel query.
    """

    if requirement.srcs.url:
        if not requirement.srcs.filename:
            logger.debug(lambda: "Could not detect the filename from the URL, falling back to pip: {}".format(
                requirement.srcs.url,
            ))
            return None, True

        # Handle direct URLs in requirements
        dist = struct(
            url = requirement.srcs.url,
            filename = requirement.srcs.filename,
            sha256 = requirement.srcs.shas[0] if requirement.srcs.shas else "",
            yanked = None,
        )

        return dist, False

    if not index_urls:
        return None, True

    whls = []
    sdist = None

    # First try to find distributions by SHA256 if provided
    shas_to_use = requirement.srcs.shas
    if not shas_to_use:
        version = requirement.srcs.version
        shas_to_use = index_urls.sha256s_by_version.get(version, [])
        logger.warn(lambda: "requirement file has been generated without hashes, will use all hashes for the given version {} that could find on the index:\n    {}".format(version, shas_to_use))

    for sha256 in shas_to_use:
        # For now if the artifact is marked as yanked we just ignore it.
        #
        # See https://packaging.python.org/en/latest/specifications/simple-repository-api/#adding-yank-support-to-the-simple-api

        maybe_whl = index_urls.whls.get(sha256)
        if maybe_whl and maybe_whl.yanked == None:
            whls.append(maybe_whl)
            continue

        maybe_sdist = index_urls.sdists.get(sha256)
        if maybe_sdist and maybe_sdist.yanked == None:
            sdist = maybe_sdist
            continue

        logger.warn(lambda: "Could not find a whl or an sdist with sha256={}".format(sha256))

    yanked = {}
    for dist in whls + [sdist]:
        if dist and dist.yanked != None:
            yanked.setdefault(dist.yanked, []).append(dist.filename)
    if yanked:
        logger.warn(lambda: "\n".join([
            "the following distributions got yanked:",
        ] + [
            "reason: {}\n  {}".format(reason, "\n".join(sorted(dists)))
            for reason, dists in yanked.items()
        ]))

    if not target_platform:
        # The pipstar platforms are undefined here, so we cannot do any matching
        return sdist, True

    if not whls and not sdist:
        # If there are no suitable wheels to handle for now allow fallback to pip, it
        # may be a little bit more helpful when debugging? Most likely something is
        # going a bit wrong here, should we raise an error because the sha256 have most
        # likely mismatched? We are already printing a warning above.
        return None, True

    # Select a single wheel that can work on the target_platform
    return select_whl(
        whls = whls,
        python_version = target_platform.env["python_full_version"],
        implementation_name = target_platform.env["implementation_name"],
        whl_abi_tags = target_platform.whl_abi_tags,
        whl_platform_tags = target_platform.whl_platform_tags,
        logger = logger,
    ) or sdist, sdist != None

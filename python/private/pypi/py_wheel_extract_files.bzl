"""Rule and loading-time glob helper for extracting files from an action-installed wheel library."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:types.bzl", "types")
load("//python/private:attr_builders.bzl", "attrb")
load("//python/private:common.bzl", "actions_run")
load("//python/private:rule_builders.bzl", "ruleb")
load(
    "//python/private:toolchain_types.bzl",
    "EXEC_TOOLS_TOOLCHAIN_TYPE",
)
load(":py_installed_wheel_info.bzl", "PyInstalledWheelInfo")

def _validate_rel_path(raw_path):
    norm = paths.normalize(raw_path)
    if (
        not raw_path or
        paths.is_absolute(raw_path) or
        norm in (".", "..") or
        norm.startswith("../")
    ):
        fail(
            "paths entries must be non-empty relative file paths within the wheel tree, got '{}'".format(
                raw_path,
            ),
        )
    return norm

def _py_wheel_extract_files_impl(ctx):
    if not ctx.attr.paths:
        return [DefaultInfo(files = depset())]

    installed_info = ctx.attr.wheel_library[PyInstalledWheelInfo]
    wheel_dir = installed_info.directory
    prefix = ctx.attr.out_prefix if ctx.attr.out_prefix else ("_extracted/" + ctx.attr.name)

    args = ctx.actions.args()
    args.add_all("--wheel-dir", [wheel_dir], expand_directories = False)
    if ctx.attr.is_executable:
        args.add("--executable")

    inputs = [wheel_dir]
    if not installed_info.keep_source and installed_info.wheel != None:
        args.add_all("--fallback-wheel", [installed_info.wheel], expand_directories = False)
        inputs.append(installed_info.wheel)
    elif not installed_info.keep_source:
        for raw_path in ctx.attr.paths:
            if raw_path.startswith("site-packages/") and raw_path.endswith(".py"):
                fail(
                    "Cannot extract .py source file '{}' from {} when precompile_source_retention is 'omit_source' and post_install_patches are applied".format(
                        raw_path,
                        ctx.attr.wheel_library.label,
                    ),
                )

    outputs = []
    if ctx.outputs.outs:
        if len(ctx.outputs.outs) != len(ctx.attr.paths):
            fail(
                "outs length ({}) must match paths length ({})".format(
                    len(ctx.outputs.outs),
                    len(ctx.attr.paths),
                ),
            )
        for raw_path, out_file in zip(ctx.attr.paths, ctx.outputs.outs):
            norm = _validate_rel_path(raw_path)
            outputs.append(out_file)
            args.add("--entry", "{}={}".format(norm, out_file.path))
    else:
        seen = {}
        for raw_path in ctx.attr.paths:
            norm = _validate_rel_path(raw_path)
            if norm in seen:
                continue
            seen[norm] = True
            out_file = ctx.actions.declare_file(paths.join(prefix, norm))
            outputs.append(out_file)
            args.add("--entry", "{}={}".format(norm, out_file.path))

    actions_run(
        ctx,
        executable = ctx.attr._wheel_files_extractor,
        arguments = [args],
        env = {
            "PYTHONDONTWRITEBYTECODE": "1",
            "PYTHONPATH": ctx.file._wheel_layout.dirname,
        },
        inputs = inputs + [ctx.file._wheel_layout],
        outputs = outputs,
        mnemonic = "PyWheelExtractFiles",
        progress_message = "Extracting {} file(s) from {} for %{{label}}".format(
            len(outputs),
            wheel_dir.short_path,
        ),
    )

    return [
        DefaultInfo(
            files = depset(outputs),
            runfiles = ctx.runfiles(files = outputs),
        ),
    ]

py_wheel_extract_files = ruleb.Rule(
    implementation = _py_wheel_extract_files_impl,
    doc = """Extracts individual files at known relative paths from an installed wheel library.

Given a target providing `PyInstalledWheelInfo` (such as a `py_wheel_library` target or
`@pypi//<pkg>:srcs` when `experimental_action_install` is enabled), this rule copies each
path in `paths` out of the installed wheel directory tree into a declared output `File`
(reflecting any `py_wheel_transform` or `post_install_patches` applied to the wheel).

:::{versionadded} VERSION_NEXT_FEATURE
:::
""",
    attrs = {
        "is_executable": lambda: attrb.Bool(
            default = False,
            doc = "If True, marks the extracted files as executable (`chmod +x`).",
        ),
        "out_prefix": lambda: attrb.String(
            default = "",
            doc = """
Optional package-relative directory prefix under which extracted files are declared
when `outs` is not specified. Defaults to `_extracted/<name>` to avoid colliding with
the wheel's `:srcs` directory.
""",
        ),
        "outs": lambda: attrb.OutputList(
            doc = """
Optional list of predeclared output files, one per entry in `paths`. When set, each
entry in `outs` is addressable as a file label in the package at loading time.
""",
        ),
        "paths": lambda: attrb.StringList(
            mandatory = True,
            doc = """
Relative file paths within the installed wheel tree root (e.g.
`["site-packages/my_pkg/data.json", "bin/my_tool", "include/my_pkg/hdr.h"]`)
to extract as individual `File` outputs.
""",
        ),
        "wheel_library": lambda: attrb.Label(
            mandatory = True,
            providers = [PyInstalledWheelInfo],
            doc = """
A target providing `PyInstalledWheelInfo` (such as a `py_wheel_library` target or
`@pypi//<pkg>:srcs` when `experimental_action_install` is enabled).
""",
        ),
        "_wheel_files_extractor": lambda: attrb.Label(
            cfg = "exec",
            default = Label("//python/private/pypi:wheel_files_extractor"),
        ),
        "_wheel_layout": lambda: attrb.Label(
            allow_single_file = True,
            default = Label("//python/private/pypi:wheel_layout.py"),
        ),
    },
    toolchains = [
        ruleb.ToolchainType(EXEC_TOOLS_TOOLCHAIN_TYPE, mandatory = True),
    ],
).build()

def _match_segment(pat, seg):
    """Match a single path segment against a wildcard pattern with `*` and `?`."""
    if pat == "*":
        return True
    if "*" not in pat and "?" not in pat:
        return pat == seg
    n = len(seg)
    dp = [True] + [False] * n
    for pch in pat.elems():
        if pch == "*":
            running = False
            next_dp = []
            for j in range(n + 1):
                if dp[j]:
                    running = True
                next_dp.append(running)
            dp = next_dp
        else:
            next_dp = [False]
            for j in range(n):
                next_dp.append(dp[j] and (pch == "?" or pch == seg[j]))
            dp = next_dp
    return dp[n]

def _match_glob_pattern(pattern, path):
    """Match a slash-separated path against a glob pattern supporting `*`, `?`, and `**`."""
    pat_segs = [s for s in pattern.split("/") if s]
    path_segs = [s for s in path.split("/") if s]
    m = len(path_segs)
    dp = [True] + [False] * m
    for pseg in pat_segs:
        if pseg == "**":
            running = False
            next_dp = []
            for j in range(m + 1):
                if dp[j]:
                    running = True
                next_dp.append(running)
            dp = next_dp
        else:
            next_dp = [False]
            for j in range(m):
                next_dp.append(dp[j] and _match_segment(pseg, path_segs[j]))
            dp = next_dp
    return dp[m]

def match_wheel_glob(files, include, exclude = [], allow_empty = True, _fail = fail):
    """Evaluate `include` / `exclude` glob patterns against `files` at loading time.

    Args:
        files: {type}`list[str]` Candidate relative file paths in the wheel tree.
        include: {type}`list[str]` Glob patterns to include (`*`, `?`, `**`).
        exclude: {type}`list[str]` Glob patterns to exclude.
        allow_empty: {type}`bool` If False, fail when no files match.
        _fail: {type}`callable` Fail function for testing.

    Returns:
        Sorted list of matching file paths from `files`.
    """
    if not (types.is_list(include) or types.is_tuple(include)):
        _fail("wheel_glob 'include' argument must be a list or tuple of strings, got {}".format(type(include)))
        return []
    if not (types.is_list(exclude) or types.is_tuple(exclude)):
        _fail("wheel_glob 'exclude' argument must be a list or tuple of strings, got {}".format(type(exclude)))
        return []

    for arg_name, pat_list in [("include", include), ("exclude", exclude)]:
        for pat in pat_list:
            if not types.is_string(pat) or not pat:
                _fail(
                    "wheel_glob '{}' patterns must be non-empty strings, got {}".format(
                        arg_name,
                        repr(pat),
                    ),
                )
                return []
            if pat.startswith("/") or pat.endswith("/") or "//" in pat:
                _fail(
                    "wheel_glob '{}' pattern '{}' must not have leading, trailing, or consecutive slashes".format(
                        arg_name,
                        pat,
                    ),
                )
                return []
            for seg in pat.split("/"):
                if seg in (".", ".."):
                    _fail(
                        "wheel_glob '{}' pattern '{}' must not contain '.' or '..' segments".format(
                            arg_name,
                            pat,
                        ),
                    )
                    return []
                if "**" in seg and seg != "**":
                    _fail(
                        "wheel_glob '{}' pattern '{}' contains invalid '**' segment '{}' ('**' must be a full path segment)".format(
                            arg_name,
                            pat,
                            seg,
                        ),
                    )
                    return []

    matched = {}
    for f in files:
        inc = False
        for pat in include:
            if _match_glob_pattern(pat, f):
                inc = True
                break
        if not inc:
            continue
        exc = False
        for pat in exclude:
            if _match_glob_pattern(pat, f):
                exc = True
                break
        if not exc:
            matched[f] = True

    result = sorted(matched.keys())
    if not result and not allow_empty:
        _fail(
            "wheel_glob pattern(s) {} did not match any files in wheel (allow_empty = False)".format(
                include,
            ),
        )
    return result

_DEFAULT_MODE_REPO_EXCLUDES = [
    "BUILD",
    "BUILD.bazel",
    "MODULE.bazel",
    "REPO.bazel",
    "WORKSPACE",
    "WORKSPACE.bzlmod",
    "WORKSPACE.bazel",
    "metadata.json",
    "wheel_files.bzl",
    "*.whl",
    "*.tar.gz",
    "*.tgz",
    "*.zip",
    "rewrite-bin/**",
    "rewrite-record/**",
]

def _collect_default_mode_excludes(exclude, native, has_existing_rule):
    default_excludes = list(_DEFAULT_MODE_REPO_EXCLUDES)
    whl_file_rule = native.existing_rule("whl_file") if has_existing_rule else None
    if whl_file_rule != None:
        for src_label in whl_file_rule.get("srcs", ()):
            clean_src = src_label.lstrip(":")
            if clean_src and clean_src not in default_excludes:
                default_excludes.append(clean_src)
    for item in exclude:
        if item not in default_excludes:
            default_excludes.append(item)
    return default_excludes

def _is_sdist_wheel_install(install_rule, native, has_existing_rule):
    sdist_rule = (
        (native.existing_rule("whldir") or native.existing_rule("_sdist_whl")) if has_existing_rule else None
    )
    if sdist_rule != None or install_rule == None:
        return sdist_rule != None
    if install_rule.get("site_paths"):
        return True
    if install_rule.get("wheel") in (":whldir", "whldir", ":_sdist_whl", "_sdist_whl"):
        return True
    return (
        install_rule.get("kind") == "py_wheel_library" and
        not install_rule.get("extracted_files") and
        not install_rule.get("shebang_scripts")
    )

def wheel_extract_prefix(*, is_executable = False, native = native):
    """Return the package-relative output directory prefix used by `wheel_glob` in the current package.

    Returns `"_extracted/"` (or `"_extracted_exec/"` when `is_executable = True`) when
    `experimental_action_install` is active in the package, or `""` in default mode,
    allowing mode-agnostic `includes = [wheel_extract_prefix() + "site-packages/pkg/include"]`.

    :::{versionadded} VERSION_NEXT_FEATURE
    :::

    Args:
        is_executable: {type}`bool` Whether executable extraction prefix is requested.
        native: {type}`struct` Native module (overridable in tests).

    Returns:
        {type}`str` Output path prefix (`"_extracted/"`, `"_extracted_exec/"`, or `""`).
    """
    has_existing_rule = hasattr(native, "existing_rule")
    wheel_install_rule = native.existing_rule("_wheel_install") if has_existing_rule else None
    srcs_rule = native.existing_rule("srcs") if has_existing_rule else None
    install_rule = wheel_install_rule if wheel_install_rule != None else srcs_rule
    if install_rule != None and install_rule.get("kind") == "py_wheel_library":
        return "_extracted_exec/" if is_executable else "_extracted/"
    return ""

def wheel_glob(
        include,
        exclude = [],
        exclude_directories = 1,
        allow_empty = True,
        *,
        files = None,
        wheel_library = None,
        is_executable = False,
        native = native,
        extract_rule = py_wheel_extract_files,
        _state = None,
        _fail = fail):
    """Glob over a downloaded wheel's known file list at loading time and extract matches.

    Usable in `additive_build_content` and in `.bzl` macros it loads as a drop-in
    replacement for `native.glob(...)` when `experimental_action_install` is enabled.
    Matches `include` / `exclude` against the wheel's `FILES` list, instantiates
    `py_wheel_extract_files` for matched paths (de-duplicating across calls in the
    same package), and returns the predeclared output file labels.

    :::{note}
    In `additive_build_content`, `wheel_glob` is auto-loaded in both default and
    `experimental_action_install` modes. However, the per-wheel `:wheel_files.bzl` file
    (for external `load("@pypi_...//:wheel_files.bzl", "wheel_glob", "FILES")`) is
    generated only when `experimental_action_install` is enabled (and its default
    `wheel_library = Label("//:_wheel_install")` target is an internal implementation
    detail exposed solely for cross-package `wheel_files.bzl` loads, not a public API).
    :::

    :::{note}
    Returned file paths differ between modes: under `experimental_action_install`,
    labels are emitted under `:_extracted/<path>` (or `:_extracted_exec/<path>` when
    `is_executable = True`), whereas in default mode `wheel_glob` delegates to
    `native.glob` (excluding repository bookkeeping files) and returns `<path>` directly
    (ignoring `is_executable` and rewritten `bin/<shebang>` scripts). Do not hardcode
    `"_extracted/..."` in attributes like `cc_import`/`cc_library` `includes`; use
    `py_wheel_headers` or `wheel_extract_prefix() + "<path>"` instead.
    :::

    :::{versionadded} VERSION_NEXT_FEATURE
    :::

    Args:
        include: {type}`list[str]` Glob patterns to include (`*`, `?`, `**`).
        exclude: {type}`list[str]` Glob patterns to exclude.
        exclude_directories: {type}`int` Must be `0` or `1` (for `native.glob` compatibility;
            wheel `FILES` contains only files).
        allow_empty: {type}`bool` Whether to allow an empty match result.
        files: {type}`list[str] | None` Optional explicit list of wheel file paths (e.g. `FILES`
            from `:wheel_files.bzl`). When omitted, discovered automatically from the current
            package's `py_wheel_library` target.
        wheel_library: {type}`str | Label | None` Target providing `PyInstalledWheelInfo`.
            Defaults to `":_wheel_install"` if present in the package, else `":srcs"`.
        is_executable: {type}`bool` Whether extracted files should have the executable bit set.
        native: {type}`struct` Native module (overridable in tests).
        extract_rule: {type}`callable` Rule used to extract files (overridable in tests).
        _state: {type}`dict | None` Optional per-package state dict for mock tests without
            `native.existing_rule`.
        _fail: {type}`callable` Fail function (overridable in tests).

    Returns:
        {type}`list[str]` Labels of the extracted output `File` targets.
    """
    if exclude_directories not in (0, 1):
        _fail(
            "wheel_glob 'exclude_directories' argument must be 0 or 1, got {}".format(
                exclude_directories,
            ),
        )
        return []
    has_existing_rule = hasattr(native, "existing_rule")
    wheel_install_rule = native.existing_rule("_wheel_install") if has_existing_rule else None
    srcs_rule = native.existing_rule("srcs") if has_existing_rule else None
    install_rule = wheel_install_rule if wheel_install_rule != None else srcs_rule

    if wheel_library == None:
        wheel_library = ":_wheel_install" if wheel_install_rule != None else ":srcs"

    if files == None:
        if _is_sdist_wheel_install(install_rule, native, has_existing_rule):
            _fail(
                "wheel_glob() cannot be used with an action-built sdist because wheel contents " +
                "are not known at loading time under experimental_action_install. Use a " +
                "pre-built wheel or py_wheel_headers / py_wheel_transform instead.",
            )
            return []
        if install_rule != None and install_rule.get("kind") != "py_wheel_library" and hasattr(native, "glob"):
            return native.glob(
                include,
                exclude = _collect_default_mode_excludes(exclude, native, has_existing_rule),
                exclude_directories = exclude_directories,
                allow_empty = allow_empty,
            )
        if install_rule == None or install_rule.get("kind") != "py_wheel_library":
            _fail(
                "wheel_glob() requires either 'files' to be passed explicitly or an " +
                "action-installed py_wheel_library target ('srcs') in the current package.",
            )
            return []
        files = list(install_rule.get("extracted_files", ()))
        for s in install_rule.get("shebang_scripts", ()):
            bin_s = "bin/" + s
            if bin_s not in files:
                files.append(bin_s)

    matched = match_wheel_glob(
        files,
        include,
        exclude = exclude,
        allow_empty = allow_empty,
        _fail = _fail,
    )
    if not matched:
        return []

    rule_prefix = "_wheel_extract_exec" if is_executable else "_wheel_extract"
    out_dir = "_extracted_exec" if is_executable else "_extracted"
    already_extracted = {}
    next_idx = 0

    if has_existing_rule:
        for i in range(10000):
            existing = native.existing_rule("{}_{}".format(rule_prefix, i))
            if existing == None:
                next_idx = i
                break
            for p in existing.get("paths", ()):
                already_extracted[p] = True
    elif _state != None:
        already_extracted = _state.setdefault(rule_prefix + "_paths", {})
        next_idx = _state.get(rule_prefix + "_idx", 0)

    new_paths = [p for p in matched if p not in already_extracted]
    if new_paths:
        for p in new_paths:
            already_extracted[p] = True
        if _state != None and not has_existing_rule:
            _state[rule_prefix + "_idx"] = next_idx + 1
        extract_kwargs = dict(
            name = "{}_{}".format(rule_prefix, next_idx),
            wheel_library = wheel_library,
            paths = new_paths,
            outs = ["{}/{}".format(out_dir, p) for p in new_paths],
            visibility = ["//visibility:private"],
        )
        if is_executable:
            extract_kwargs["is_executable"] = True
        extract_rule(**extract_kwargs)

    return [":{}/{}".format(out_dir, p) for p in matched]

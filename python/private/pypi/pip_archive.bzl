""

load("//python/private:auth.bzl", "get_auth")
load("//python/private:envsubst.bzl", "envsubst")
load("//python/private:is_standalone_interpreter.bzl", "is_standalone_interpreter")
load("//python/private:repo_utils.bzl", "REPO_DEBUG_ENV_VAR", "repo_utils")
load(":attrs.bzl", "ATTRS", "use_isolated")
load(":deps.bzl", "all_repo_names", "record_files")
load(":patch_and_extract_whl.bzl", "patch_and_extract_whl")
load(":pypi_repo_utils.bzl", "pypi_repo_utils")
load(":urllib.bzl", "urllib")
load(":whl_archive.bzl", "whl_archive_attrs")

_CPPFLAGS = "CPPFLAGS"
_COMMAND_LINE_TOOLS_PATH_SLUG = "commandlinetools"

def _get_xcode_location_cflags(rctx, logger = None):
    """Query the xcode sdk location to update cflags

    Figure out if this interpreter target comes from rules_python, and patch the xcode sdk location if so.
    Pip won't be able to compile c extensions from sdists with the pre built python distributions from astral-sh
    otherwise. See https://github.com/astral-sh/python-build-standalone/issues/103
    """

    # Only run on MacOS hosts
    if not rctx.os.name.lower().startswith("mac os"):
        return []

    xcode_sdk_location = repo_utils.execute_unchecked(
        rctx,
        op = "GetXcodeLocation",
        arguments = [repo_utils.which_checked(rctx, "xcode-select"), "--print-path"],
        logger = logger,
    )
    if xcode_sdk_location.return_code != 0:
        return []

    xcode_root = xcode_sdk_location.stdout.strip()
    if _COMMAND_LINE_TOOLS_PATH_SLUG not in xcode_root.lower():
        # This is a full xcode installation somewhere like /Applications/Xcode13.0.app/Contents/Developer
        # so we need to change the path to to the macos specific tools which are in a different relative
        # path than xcode installed command line tools.
        xcode_sdks_json = repo_utils.execute_checked(
            rctx,
            op = "LocateXCodeSDKs",
            arguments = [
                repo_utils.which_checked(rctx, "xcrun"),
                "xcodebuild",
                "-showsdks",
                "-json",
            ],
            environment = {
                "DEVELOPER_DIR": xcode_root,
            },
            logger = logger,
        ).stdout
        xcode_sdks = json.decode(xcode_sdks_json)
        potential_sdks = [
            sdk
            for sdk in xcode_sdks
            if "productName" in sdk and
               sdk["productName"] == "macOS" and
               "darwinos" not in sdk["canonicalName"]
        ]

        # Now we'll get two entries here (one for internal and another one for public)
        # It shouldn't matter which one we pick.
        xcode_sdk_path = potential_sdks[0]["sdkPath"]
    else:
        xcode_sdk_path = "{}/SDKs/MacOSX.sdk".format(xcode_root)

    return [
        "-isysroot {}".format(xcode_sdk_path),
    ]

def _get_toolchain_unix_cflags(rctx, python_interpreter, logger = None):
    """Gather cflags from a standalone toolchain for unix systems.

    Pip won't be able to compile c extensions from sdists with the pre built python distributions from astral-sh
    otherwise. See https://github.com/astral-sh/python-build-standalone/issues/103
    """

    # Only run on Unix systems
    if not rctx.os.name.lower().startswith(("mac os", "linux")):
        return []

    # Only update the location when using a standalone toolchain.
    if not is_standalone_interpreter(rctx, python_interpreter, logger = logger):
        return []

    stdout = pypi_repo_utils.execute_checked_stdout(
        rctx,
        op = "GetPythonVersionForUnixCflags",
        # python_interpreter by default points to a symlink, however when using bazel in vendor mode,
        # and the vendored directory moves around, the execution of python fails, as it's getting confused
        # where it's running from. More to the fact that we are executing it in isolated mode "-I", which
        # results in PYTHONHOME being ignored. The solution is to run python from it's real directory.
        python = python_interpreter.realpath,
        arguments = [
            # Run the interpreter in isolated mode, this options implies -E, -P and -s.
            # Ensures environment variables are ignored that are set in userspace, such as PYTHONPATH,
            # which may interfere with this invocation.
            "-I",
            "-c",
            "import sys; print(f'{sys.version_info[0]}.{sys.version_info[1]}', end='')",
        ],
        srcs = [],
        logger = logger,
    )
    _python_version = stdout
    include_path = "{}/include/python{}".format(
        python_interpreter.dirname,
        _python_version,
    )

    return ["-isystem {}".format(include_path)]

def _parse_optional_attrs(rctx, args, extra_pip_args = None):
    """Helper function to parse common attributes of pip_repository and whl_library repository rules.

    This function also serializes the structured arguments as JSON
    so they can be passed on the command line to subprocesses.

    Args:
        rctx: Handle to the rule repository context.
        args: A list of parsed args for the rule.
        extra_pip_args: The pip args to pass.
    Returns: Augmented args list.
    """

    if use_isolated(rctx, rctx.attr):
        args.append("--isolated")

    # Check for None so we use empty default types from our attrs.
    # Some args want to be list, and some want to be dict.
    if extra_pip_args != None:
        args += [
            "--extra_pip_args",
            json.encode(struct(arg = [
                envsubst(pip_arg, rctx.attr.envsubst, rctx.getenv)
                for pip_arg in extra_pip_args
            ])),
        ]

    if rctx.attr.download_only:
        args.append("--download_only")

    if rctx.attr.pip_data_exclude != None:
        args += [
            "--pip_data_exclude",
            json.encode(struct(arg = rctx.attr.pip_data_exclude)),
        ]

    env = {}
    if rctx.attr.environment != None:
        for key, value in rctx.attr.environment.items():
            env[key] = value

    # This is super hacky, but working out something nice is tricky.
    # This is in particular needed for psycopg2 which attempts to link libpython.a,
    # in order to point the linker at the correct python intepreter.
    if rctx.attr.add_libdir_to_library_search_path:
        if "LDFLAGS" in env:
            fail("Can't set both environment LDFLAGS and add_libdir_to_library_search_path")
        command = [
            pypi_repo_utils.resolve_python_interpreter(rctx),
            "-c",
            "import sys ; sys.stdout.write('{}/lib'.format(sys.exec_prefix))",
        ]
        result = rctx.execute(command)
        if result.return_code != 0:
            fail("Failed to get LDFLAGS path: command: {}, exit code: {}, stdout: {}, stderr: {}".format(command, result.return_code, result.stdout, result.stderr))
        libdir = result.stdout
        env["LDFLAGS"] = "-L{}".format(libdir)

    args += [
        "--environment",
        json.encode(struct(arg = env)),
    ]

    return args

def _get_python_home(rctx, python_interpreter, logger = None):
    """Get the PYTHONHOME directory from the selected python interpretter

    Args:
        rctx (repository_ctx): The repository context.
        python_interpreter (path): The resolved python interpreter.
        logger: Optional logger to use for operations.
    Returns:
        String of PYTHONHOME directory.
    """

    return pypi_repo_utils.execute_checked_stdout(
        rctx,
        op = "GetPythonHome",
        # python_interpreter by default points to a symlink, however when using bazel in vendor mode,
        # and the vendored directory moves around, the execution of python fails, as it's getting confused
        # where it's running from. More to the fact that we are executing it in isolated mode "-I", which
        # results in PYTHONHOME being ignored. The solution is to run python from it's real directory.
        python = python_interpreter.realpath,
        arguments = [
            # Run the interpreter in isolated mode, this options implies -E, -P and -s.
            # Ensures environment variables are ignored that are set in userspace, such as PYTHONPATH,
            # which may interfere with this invocation.
            "-I",
            "-c",
            "import sys; print(f'{sys.prefix}', end='')",
        ],
        srcs = [],
        logger = logger,
    )

def _create_repository_execution_environment(rctx, python_interpreter, logger = None):
    """Create a environment dictionary for processes we spawn with rctx.execute.

    Args:
        rctx (repository_ctx): The repository context.
        python_interpreter (path): The resolved python interpreter.
        logger: Optional logger to use for operations.
    Returns:
        Dictionary of environment variable suitable to pass to rctx.execute.
    """

    env = {
        "PYTHONHOME": _get_python_home(rctx, python_interpreter, logger),
        "PYTHONPATH": pypi_repo_utils.construct_pythonpath(
            rctx,
            entries = rctx.attr._python_path_entries,
        ),
    }

    # Gather any available CPPFLAGS values
    #
    # We may want to build in an environment without a cc toolchain.
    # In those cases, we're limited to --download-only, but we should respect that here.
    is_wheel = rctx.attr.filename and rctx.attr.filename.endswith(".whl")
    if not (rctx.attr.download_only or is_wheel):
        cppflags = []
        cppflags.extend(_get_xcode_location_cflags(rctx, logger = logger))
        cppflags.extend(_get_toolchain_unix_cflags(rctx, python_interpreter, logger = logger))
        env[_CPPFLAGS] = " ".join(cppflags)
    return env

def _pip_archive_impl(rctx):
    logger = repo_utils.logger(rctx)

    sdist_filename = None
    extra_pip_args = []
    extra_pip_args.extend(rctx.attr.extra_pip_args)
    if rctx.attr.urls and rctx.attr.filename:
        filename = rctx.attr.filename
        urls = rctx.attr.urls
        urls = [
            urllib.absolute_url(
                rctx.attr.index_url,
                url,
                envsubst = rctx.attr.envsubst,
                getenv = rctx.getenv,
            )
            for url in urls
        ]
        result = rctx.download(
            url = urls,
            output = filename,
            sha256 = rctx.attr.sha256,
            integrity = rctx.attr.integrity if not rctx.attr.sha256 else "",
            auth = get_auth(rctx, urls),
        )
        if not rctx.attr.sha256 and not rctx.attr.integrity:
            # this is only seen when there is a direct URL reference without a hash
            logger.warn("Please update the requirement line to include the hash:\n{} \\\n    --hash=sha256:{}".format(
                rctx.attr.requirement,
                result.sha256,
            ))

        if not result.success:
            fail("could not download the '{}' from {}:\n{}".format(filename, urls, result))

        if filename.endswith(".whl"):
            fail("Only sdists are supported")
        else:
            sdist_filename = filename

            # It is an sdist and we need to tell PyPI to use a file in this directory
            # and, allow getting build dependencies from PYTHONPATH, which we
            # setup in this repository rule, but still download any necessary
            # build deps from PyPI (e.g. `flit_core`) if they are missing.
            extra_pip_args.extend(["--find-links", "."])

    # When we already have a wheel, Python isn't used,
    # so there's no need to setup env vars to run Python, unless we need to
    # build an sdist or resolve a requirement.
    python_interpreter = pypi_repo_utils.resolve_python_interpreter(
        rctx,
        python_interpreter = rctx.attr.python_interpreter,
        python_interpreter_target = rctx.attr.python_interpreter_target,
    )
    args = [
        "-m",
        "python.private.pypi.whl_installer.wheel_installer",
        "--requirement",
        rctx.attr.requirement,
    ]
    args = _parse_optional_attrs(rctx, args, extra_pip_args)

    # Manually construct the PYTHONPATH since we cannot use the toolchain here
    environment = _create_repository_execution_environment(rctx, python_interpreter, logger = logger)

    if rctx.attr.urls:
        op_tmpl = "whl_library.BuildWheelFromSource({name}, {requirement})"
    elif rctx.attr.download_only:
        op_tmpl = "whl_library.DownloadWheel({name}, {requirement})"
    else:
        op_tmpl = "whl_library.ResolveRequirement({name}, {requirement})"

    pypi_repo_utils.execute_checked(
        rctx,
        # truncate the requirement value when logging it / reporting
        # progress since it may contain several ' --hash=sha256:...
        # --hash=sha256:...' substrings that fill up the console
        python = python_interpreter,
        op = op_tmpl.format(name = rctx.attr.name, requirement = rctx.attr.requirement.split(" ", 1)[0]),
        arguments = args,
        environment = environment,
        srcs = rctx.attr._python_srcs,
        quiet = rctx.attr.quiet,
        timeout = rctx.attr.timeout,
        logger = logger,
    )

    whl_path = rctx.path(json.decode(rctx.read("whl_file.json"))["whl_file"])
    if not rctx.delete("whl_file.json"):
        fail("failed to delete the whl_file.json file")

    # NOTE @aignas 2026-08-14: We never return rctx.metadata for pip archives because the result may
    # not be reproducible across all machines given the input args to the repository rule.
    patch_and_extract_whl(rctx, whl_path = whl_path, logger = logger, sdist_filename = sdist_filename)

# NOTE @aignas 2024-03-21: The usage of dict({}, **common) ensures that all args to `dict` are unique
pip_archive_attrs = whl_archive_attrs | {
    k: ATTRS[k]
    for k in [
        # used for pulling deps with pip
        "download_only",
        "add_libdir_to_library_search_path",
        "environment",
        "extra_pip_args",
        "isolated",
        "python_interpreter",
        "python_interpreter_target",
        "quiet",
        "timeout",
    ]
}

pip_archive = repository_rule(
    attrs = pip_archive_attrs | {
        "_python_path_entries": attr.label_list(
            # Get the root directory of these rules and keep them as a default attribute
            # in order to avoid unnecessary repository fetching restarts.
            #
            # This is very similar to what was done in https://github.com/bazelbuild/rules_go/pull/3478
            default = [
                Label("//:BUILD.bazel"),
            ] + [
                # Includes all the external dependencies from repositories.bzl
                Label("@" + repo + "//:BUILD.bazel")
                for repo in all_repo_names
            ],
        ),
        "_python_srcs": attr.label_list(
            # Used as a default value in a rule to ensure we fetch the dependencies.
            default = [
                Label("//python/private/pypi/whl_installer:wheel_installer.py"),
                Label("//python/private/pypi/whl_installer:arguments.py"),
            ] + record_files.values(),
        ),
        "_rule_name": attr.string(default = "pip_archive"),
    },
    doc = """
Download and extracts a single wheel based into a bazel repo based on the requirement string passed in.
Instantiated from pip_repository and inherits config options from there.

:::{versionchanged} 1.9.0
The `whl_library` is marked as reproducible if using starlark to extract and parse the
wheel contents without building an `sdist` first.
:::

:::{versionchanged} 2.3.0
The whl-only pure Starlark operations have been refactored into {obj}`whl_archive` and the
previously named {obj}`whl_library` repository became renamed to `pip_archive`.
:::
""",
    implementation = _pip_archive_impl,
    environ = [
        "RULES_PYTHON_PIP_ISOLATED",
        REPO_DEBUG_ENV_VAR,
    ],
)

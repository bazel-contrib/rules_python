# Copyright 2023 The Bazel Authors. All rights reserved.
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

"pip module extension for use with bzlmod"

load("@pythons_hub//:interpreters.bzl", "DEFAULT_PYTHON_VERSION", "INTERPRETER_LABELS")
load("@rules_python//python:pip.bzl", "whl_library_alias")
load(
    "@rules_python//python/pip_install:pip_repository.bzl",
    "locked_requirements_label",
    "pip_hub_repository_bzlmod",
    "pip_repository_attrs",
    "pip_repository_bzlmod",
    "use_isolated",
    "whl_library",
)
load("@rules_python//python/pip_install:requirements_parser.bzl", parse_requirements = "parse")

def _create_versioned_pip_and_whl_repos(module_ctx, pip_attr, whl_map):
    python_interpreter_target = pip_attr.python_interpreter_target

    # if we do not have the python_interpreter set in the attributes
    # we programtically find it.
    hub_name = pip_attr.hub_name
    if python_interpreter_target == None:
        python_name = "python_{}".format(pip_attr.python_version.replace(".", "_"))
        if python_name not in INTERPRETER_LABELS.keys():
            fail((
                "Unable to find interpreter for pip hub '{hub_name}' for " +
                "python_version={version}: Make sure a corresponding " +
                '`python.toolchain(python_version="{version}")` call exists'
            ).format(
                hub_name = hub_name,
                version = pip_attr.python_version,
            ))
        python_interpreter_target = INTERPRETER_LABELS[python_name]

    pip_name = hub_name + "_{}".format(pip_attr.python_version.replace(".", ""))
    requrements_lock = locked_requirements_label(module_ctx, pip_attr)

    # Parse the requirements file directly in starlark to get the information
    # needed for the whl_libary declarations below. This is needed to contain
    # the pip_repository logic to a single module extension.
    requirements_lock_content = module_ctx.read(requrements_lock)
    parse_result = parse_requirements(requirements_lock_content)
    requirements = parse_result.requirements
    extra_pip_args = pip_attr.extra_pip_args + parse_result.options

    # Create the repository where users load the `requirement` macro. Under bzlmod
    # this does not create the install_deps() macro.
    # TODO: we may not need this repository once we have entry points
    # supported. For now a user can access this repository and use
    # the entrypoint functionality.
    pip_repository_bzlmod(
        name = pip_name,
        repo_name = pip_name,
        requirements_lock = pip_attr.requirements_lock,
    )
    if hub_name not in whl_map:
        whl_map[hub_name] = {}

    # Create a new wheel library for each of the different whls
    for whl_name, requirement_line in requirements:
        whl_name = _sanitize_name(whl_name)
        whl_library(
            name = "%s_%s" % (pip_name, whl_name),
            requirement = requirement_line,
            repo = pip_name,
            repo_prefix = pip_name + "_",
            annotation = pip_attr.annotations.get(whl_name),
            python_interpreter = pip_attr.python_interpreter,
            python_interpreter_target = python_interpreter_target,
            quiet = pip_attr.quiet,
            timeout = pip_attr.timeout,
            isolated = use_isolated(module_ctx, pip_attr),
            extra_pip_args = extra_pip_args,
            download_only = pip_attr.download_only,
            pip_data_exclude = pip_attr.pip_data_exclude,
            enable_implicit_namespace_pkgs = pip_attr.enable_implicit_namespace_pkgs,
            environment = pip_attr.environment,
        )

        if whl_name not in whl_map[hub_name]:
            whl_map[hub_name][whl_name] = {}

        whl_map[hub_name][whl_name][pip_attr.python_version] = pip_name + "_"

def _pip_impl(module_ctx):
    """Implementation of a class tag that creates the pip hub(s) and corresponding pip spoke, alias and whl repositories.

    This implmentation iterates through all of the `pip.parse` calls and creates
    different pip hub repositories based on the "hub_name".  Each of the
    pip calls create spoke repos that uses a specific Python interpreter.

    In a MODULES.bazel file we have:

    pip.parse(
        hub_name = "pip",
        python_version = 3.9,
        requirements_lock = "//:requirements_lock_3_9.txt",
        requirements_windows = "//:requirements_windows_3_9.txt",
    )
    pip.parse(
        hub_name = "pip",
        python_version = 3.10,
        requirements_lock = "//:requirements_lock_3_10.txt",
        requirements_windows = "//:requirements_windows_3_10.txt",
    )


    For instance, we have a hub with the name of "pip".
    A repository named the following is created. It is actually called last when
    all of the pip spokes are collected.

    - @@rules_python~override~pip~pip

    As shown in the example code above we have the following.
    Two different pip.parse statements exist in MODULE.bazel provide the hub_name "pip".
    These definitions create two different pip spoke repositories that are
    related to the hub "pip".
    One spoke uses Python 3.9 and the other uses Python 3.10. This code automatically
    determines the Python version and the interpreter.
    Both of these pip spokes contain requirements files that includes websocket
    and its dependencies.

    Two different repositories are created for the two spokes:

    - @@rules_python~override~pip~pip_39
    - @@rules_python~override~pip~pip_310

    The different spoke names are a combination of the hub_name and the Python version.
    In the future we may remove this repository, but we do not support entry points.
    yet, and that functionality exists in these repos.

    We also need repositories for the wheels that the different pip spokes contain.
    For each Python version a different wheel repository is created. In our example
    each pip spoke had a requirments file that contained websockets. We
    then create two different wheel repositories that are named the following.

    - @@rules_python~override~pip~pip_39_websockets
    - @@rules_python~override~pip~pip_310_websockets

    And if the wheel has any other dependies subsequest wheels are created in the same fashion.

    We also create a repository for the wheel alias.  We want to just use the syntax
    'requirement("websockets")' we need to have an alias repository that is named:

    - @@rules_python~override~pip~pip_websockets

    This repository contains alias statements for the different wheel components (pkg, data, etc).
    Each of those aliases has a select that resolves to a spoke repository depending on
    the Python version.

    Also we may have more than one hub as defined in a MODULES.bazel file.  So we could have multiple
    hubs pointing to various different pip spokes.

    Some other business rules notes.  A hub can only have one spoke per Python version.  We cannot
    have a hub named "pip" that has two spokes that use the Python 3.9 interpreter.  Second
    we cannot have the same hub name used in submodules.  The hub name has to be globally
    unique.

    This implementation reuses elements of non-bzlmod code and also reuses the first implementation
    of pip bzlmod, but adds the capability to have multiple pip.parse calls.

    Args:
        module_ctx: module contents

    """

    # Used to track all the different pip hubs and the spoke pip Python
    # versions.
    pip_hub_map = {}

    # Keeps track of all the hub's whl repos across the different versions.
    # dict[hub, dict[whl, dict[version, str pip]]]
    # Where hub, whl, and pip are the repo names
    hub_whl_map = {}

    for mod in module_ctx.modules:
        for pip_attr in mod.tags.parse:
            hub_name = pip_attr.hub_name
            if hub_name in pip_hub_map:
                # We cannot have two hubs with the same name in different
                # modules.
                if pip_hub_map[hub_name].module_name != mod.name:
                    fail((
                        "Duplicate cross-module pip hub named '{hub}': pip hub " +
                        "names must be unique across modules. First defined " +
                        "by module '{first_module}', second attempted by " +
                        "module '{second_module}'"
                    ).format(
                        hub = hub_name,
                        first_module = pip_hub_map[hub_name].module_name,
                        second_module = mod.name,
                    ))

                if pip_attr.python_version in pip_hub_map[hub_name].python_versions:
                    fail((
                        "Duplicate pip python version '{version}' for hub " +
                        "'{hub}' in module '{module}': the Python versions " +
                        "used for a hub must be unique"
                    ).format(
                        hub = hub_name,
                        module = mod.name,
                        version = pip_attr.python_version,
                    ))
                else:
                    pip_hub_map[pip_attr.hub_name].python_versions.append(pip_attr.python_version)
            else:
                pip_hub_map[pip_attr.hub_name] = struct(
                    module_name = mod.name,
                    python_versions = [pip_attr.python_version],
                )

            _create_versioned_pip_and_whl_repos(module_ctx, pip_attr, hub_whl_map)

    for hub_name, whl_map in hub_whl_map.items():
        for whl_name, version_map in whl_map.items():
            if DEFAULT_PYTHON_VERSION not in version_map:
                fail((
                    "Default python version '{version}' missing in pip " +
                    "hub '{hub}': update your pip.parse() calls so that " +
                    'includes `python_version = "{version}"`'
                ).format(
                    version = DEFAULT_PYTHON_VERSION,
                    hub = hub_name,
                ))

            # Create the alias repositories which contains different select
            # statements  These select statements point to the different pip
            # whls that are based on a specific version of Python.
            whl_library_alias(
                name = hub_name + "_" + whl_name,
                wheel_name = whl_name,
                default_version = DEFAULT_PYTHON_VERSION,
                version_map = version_map,
            )

        # Create the hub repository for pip.
        pip_hub_repository_bzlmod(
            name = hub_name,
            repo_name = hub_name,
            whl_library_alias_names = whl_map.keys(),
        )

# Keep in sync with python/pip_install/tools/bazel.py
def _sanitize_name(name):
    return name.replace("-", "_").replace(".", "_").lower()

def _pip_parse_ext_attrs():
    attrs = dict({
        "hub_name": attr.string(
            mandatory = True,
            doc = """
The name of the repo pip dependencies will be accessible from.

This name must be unique between modules; unless your module is guaranteed to
always be the root module, it's highly recommended to include your module name
in the hub name. Repo mapping, `use_repo(..., pip="my_modules_pip_deps")`, can
be used for shorter local names within your module.

Within a module, the same `hub_name` can be specified to group different Python
versions of pip dependencies under one repository name. This allows using a
Python version-agnostic name when referring to pip dependencies; the
correct version will be automatically selected.

Typically, a module will only have a single hub of pip dependencies, but this
is not required. Each hub is a separate resolution of pip dependencies. This
means if different programs need different versions of some library, separate
hubs can be created, and each program can use its respective hub's targets.
Targets from different hubs should not be used together.
""",
        ),
        "python_version": attr.string(
            mandatory = True,
            doc = """
The Python version to use for resolving the pip dependencies. If not specified,
then the default Python version (as set by the root module or rules_python)
will be used.

The version specified here must have a corresponding `python.toolchain()`
configured.
""",
        ),
    }, **pip_repository_attrs)

    # Like the pip_repository rule, we end up setting this manually so
    # don't allow users to override it.
    attrs.pop("repo_prefix")

    # incompatible_generate_aliases is always True in bzlmod
    attrs.pop("incompatible_generate_aliases")

    return attrs

pip = module_extension(
    doc = """\
This extension is used to make dependencies from pip available.

To use, call `pip.parse()` and specify `hub_name` and your requirements file.
Dependencies will be downloaded and made available in a repo named after the
`hub_name` argument.

Each `pip.parse()` call configures a particular Python version. Multiple calls
can be made to configure different Python versions, and will be grouped by
the `hub_name` argument. This allows the same logical name, e.g. `@pip//numpy`
to automatically resolve to different, Python version-specific, libraries.
""",
    implementation = _pip_impl,
    tag_classes = {
        "parse": tag_class(attrs = _pip_parse_ext_attrs()),
    },
)

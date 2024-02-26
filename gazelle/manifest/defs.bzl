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

"""This module provides the gazelle_python_manifest macro that contains targets
for updating and testing the Gazelle manifest file.
"""

load("@bazel_skylib//rules:diff_test.bzl", "diff_test")
load("@io_bazel_rules_go//go:def.bzl", "GoSource", "go_test")
load("@rules_python//python:defs.bzl", "py_binary")

def gazelle_python_manifest(
        name,
        modules_mapping,
        requirements = [],
        pip_repository_name = "",
        pip_deps_repository_name = "",
        manifest = ":gazelle_python.yaml",
        **kwargs):
    """A macro for defining the updating and testing targets for the Gazelle manifest file.

    Args:
        name: the name used as a base for the targets.
        modules_mapping: the target for the generated modules_mapping.json file.
        requirements: the target for the requirements.txt file or a list of
            requirements files that will be concatenated before passing on to
            the manifest generator. If unset, no integrity field is added to the
            manifest, meaning testing it is just as expensive as generating it,
            but modifying it is much less likely to result in a merge conflict.
        pip_repository_name: the name of the pip_install or pip_repository target.
        pip_deps_repository_name: deprecated - the old pip_install target name.
        manifest: the Gazelle manifest file.
            defaults to the same value as manifest.
        **kwargs: other bazel attributes passed to the generate and test targets
            generated by this macro.
    """
    if pip_deps_repository_name != "":
        # buildifier: disable=print
        print("DEPRECATED pip_deps_repository_name in //{}:{}. Please use pip_repository_name instead.".format(
            native.package_name(),
            name,
        ))
        pip_repository_name = pip_deps_repository_name

    if pip_repository_name == "":
        # This is a temporary check while pip_deps_repository_name exists as deprecated.
        fail("pip_repository_name must be set in //{}:{}".format(native.package_name(), name))

    test_target = "{}.test".format(name)
    update_target = "{}.update".format(name)
    update_target_label = "//{}:{}".format(native.package_name(), update_target)

    manifest_genrule = name + ".genrule"
    generated_manifest = name + ".generated_manifest"
    manifest_generator = Label("//manifest/generate:generate")
    manifest_generator_hash = Label("//manifest/generate:generate_lib_sources_hash")

    if requirements and type(requirements) == "list":
        # This runs if requirements is a list or is unset (default value is empty list)
        native.genrule(
            name = name + "_requirements_gen",
            srcs = sorted(requirements),
            outs = [name + "_requirements.txt"],
            cmd_bash = "cat $(SRCS) > $@",
            cmd_bat = "type $(SRCS) > $@",
        )
        requirements = name + "_requirements_gen"

    update_args = [
        "--manifest-generator-hash=$(execpath {})".format(manifest_generator_hash),
        "--requirements=$(rootpath {})".format(requirements) if requirements else "--requirements=",
        "--pip-repository-name={}".format(pip_repository_name),
        "--modules-mapping=$(execpath {})".format(modules_mapping),
        "--output=$(execpath {})".format(generated_manifest),
        "--update-target={}".format(update_target_label),
    ]

    native.genrule(
        name = manifest_genrule,
        outs = [generated_manifest],
        cmd = "$(execpath {}) {}".format(manifest_generator, " ".join(update_args)),
        tools = [manifest_generator],
        srcs = [
            modules_mapping,
            manifest_generator_hash,
        ] + ([requirements] if requirements else []),
    )

    py_binary(
        name = update_target,
        srcs = [Label("//manifest:copy_to_source.py")],
        main = Label("//manifest:copy_to_source.py"),
        args = [
            "$(rootpath {})".format(generated_manifest),
            "$(rootpath {})".format(manifest),
        ],
        data = [
            generated_manifest,
            manifest,
        ],
        **kwargs
    )

    if requirements:
        attrs = {
            "env": {
                "_TEST_MANIFEST": "$(rootpath {})".format(manifest),
                "_TEST_MANIFEST_GENERATOR_HASH": "$(rootpath {})".format(manifest_generator_hash),
                "_TEST_REQUIREMENTS": "$(rootpath {})".format(requirements),
            },
            "size": "small",
        }
        go_test(
            name = test_target,
            srcs = [Label("//manifest/test:test.go")],
            data = [
                manifest,
                requirements,
                manifest_generator_hash,
            ],
            rundir = ".",
            deps = [Label("//manifest")],
            # kwargs could contain test-specific attributes like size or timeout
            **dict(attrs, **kwargs)
        )
    else:
        diff_test(
            name = test_target,
            file1 = generated_manifest,
            file2 = manifest,
            failure_message = "Gazelle manifest is out of date. Run 'bazel run {}' to update it.".format(native.package_relative_label(update_target)),
            **kwargs
        )

    native.filegroup(
        name = name,
        srcs = [manifest],
        tags = ["manual"],
        visibility = ["//visibility:public"],
    )

# buildifier: disable=provider-params
AllSourcesInfo = provider(fields = {"all_srcs": "All sources collected from the target and dependencies."})

_rules_python_workspace = Label("@rules_python//:WORKSPACE")

def _get_all_sources_impl(target, ctx):
    is_rules_python = target.label.workspace_name == _rules_python_workspace.workspace_name
    if not is_rules_python:
        # Avoid adding third-party dependency files to the checksum of the srcs.
        return AllSourcesInfo(all_srcs = depset())
    srcs = depset(
        target[GoSource].orig_srcs,
        transitive = [dep[AllSourcesInfo].all_srcs for dep in ctx.rule.attr.deps],
    )
    return [AllSourcesInfo(all_srcs = srcs)]

_get_all_sources = aspect(
    implementation = _get_all_sources_impl,
    attr_aspects = ["deps"],
)

def _sources_hash_impl(ctx):
    all_srcs = ctx.attr.go_library[AllSourcesInfo].all_srcs
    hash_file = ctx.actions.declare_file(ctx.attr.name + ".hash")
    args = ctx.actions.args()
    args.add(hash_file)
    args.add_all(all_srcs)
    ctx.actions.run(
        outputs = [hash_file],
        inputs = all_srcs,
        arguments = [args],
        executable = ctx.executable._hasher,
    )
    return [DefaultInfo(
        files = depset([hash_file]),
        runfiles = ctx.runfiles([hash_file]),
    )]

sources_hash = rule(
    _sources_hash_impl,
    attrs = {
        "go_library": attr.label(
            aspects = [_get_all_sources],
            providers = [GoSource],
        ),
        "_hasher": attr.label(
            cfg = "exec",
            default = Label("//manifest/hasher"),
            executable = True,
        ),
    },
)

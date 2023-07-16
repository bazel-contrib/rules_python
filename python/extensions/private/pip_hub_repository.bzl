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

"""
A pip_hub_repository rule used to create bzlmod hub repos for PyPI packages.

It assumes that version aware toolchain is used and is responsible for setting up
aliases for entry points and the actual package targets.
"""

load("//python/private:render_pkg_aliases.bzl", "render_pkg_aliases")

_BUILD_FILE_CONTENTS = """\
package(default_visibility = ["//visibility:public"])

# Ensure the `requirements.bzl` source can be accessed by stardoc, since users load() from it
exports_files(["requirements.bzl"])
"""

def _impl(rctx):
    bzl_packages = rctx.attr.whl_map.keys()
    repo_name = rctx.attr.repo_name

    aliases = render_pkg_aliases(
        repo_name = repo_name,
        whl_map = rctx.attr.whl_map,
        default_version = rctx.attr.default_version,
        rules_python = rctx.attr._template.workspace_name,
    )
    for path, contents in aliases.items():
        rctx.file(path, contents)

    # NOTE: we are using the canonical name with the double '@' in order to
    # always uniquely identify a repository, as the labels are being passed as
    # a string and the resolution of the label happens at the call-site of the
    # `requirement`, et al. macros.
    macro_tmpl = "@@{name}//{{}}:{{}}".format(name = rctx.attr.name)

    rctx.file("BUILD.bazel", _BUILD_FILE_CONTENTS)
    rctx.template("requirements.bzl", rctx.attr._template, substitutions = {
        "%%ALL_DATA_REQUIREMENTS%%": repr([
            macro_tmpl.format(p, "data")
            for p in bzl_packages
        ]),
        "%%ALL_REQUIREMENTS%%": repr([
            macro_tmpl.format(p, p)
            for p in bzl_packages
        ]),
        "%%ALL_WHL_REQUIREMENTS%%": repr([
            macro_tmpl.format(p, "whl")
            for p in bzl_packages
        ]),
        "%%DEFAULT_PY_VERSION%%": repr(rctx.attr.default_version),
        "%%MACRO_TMPL%%": macro_tmpl,
        "%%NAME%%": rctx.attr.name,
        "%%PACKAGE_AVAILABILITY%%": repr({
            k: [v for v in versions]
            for k, versions in rctx.attr.whl_map.items()
        }),
        "%%RULES_PYTHON%%": rctx.attr._template.workspace_name,
    })

pip_hub_repository = repository_rule(
    attrs = {
        "default_version": attr.string(
            mandatory = True,
            doc = """\
This is the default python version in the format of X.Y.Z. This should match
what is setup by the 'python' extension using the 'is_default = True'
setting.""",
        ),
        "repo_name": attr.string(
            mandatory = True,
            doc = "The apparent name of the repo. This is needed because in bzlmod, the name attribute becomes the canonical name.",
        ),
        "whl_map": attr.string_list_dict(
            mandatory = True,
            doc = "The wheel map where values are python versions",
        ),
        "_template": attr.label(default = ":requirements.bzl.tmpl"),
    },
    doc = """A rule for creating bzlmod hub repo for PyPI packages. PRIVATE USE ONLY.""",
    implementation = _impl,
)

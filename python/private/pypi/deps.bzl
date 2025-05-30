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

""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

_RULE_DEPS = [
    # START: maintained by 'bazel run //tools/private/update_deps:update_pip_deps'
    (
        "pypi__build",
        "https://files.pythonhosted.org/packages/84/c2/80633736cd183ee4a62107413def345f7e6e3c01563dbca1417363cf957e/build-1.2.2.post1-py3-none-any.whl",
        "1d61c0887fa860c01971625baae8bdd338e517b836a2f70dd1f7aa3a6b2fc5b5",
    ),
    (
        "pypi__click",
        "https://files.pythonhosted.org/packages/7e/d4/7ebdbd03970677812aac39c869717059dbb71a4cfc033ca6e5221787892c/click-8.1.8-py3-none-any.whl",
        "63c132bbbed01578a06712a2d1f497bb62d9c1c0d329b7903a866228027263b2",
    ),
    (
        "pypi__colorama",
        "https://files.pythonhosted.org/packages/d1/d6/3965ed04c63042e047cb6a3e6ed1a63a35087b6a609aa3a15ed8ac56c221/colorama-0.4.6-py2.py3-none-any.whl",
        "4f1d9991f5acc0ca119f9d443620b77f9d6b33703e51011c16baf57afb285fc6",
    ),
    (
        "pypi__importlib_metadata",
        "https://files.pythonhosted.org/packages/20/b0/36bd937216ec521246249be3bf9855081de4c5e06a0c9b4219dbeda50373/importlib_metadata-8.7.0-py3-none-any.whl",
        "e5dd1551894c77868a30651cef00984d50e1002d06942a7101d34870c5f02afd",
    ),
    (
        "pypi__installer",
        "https://files.pythonhosted.org/packages/e5/ca/1172b6638d52f2d6caa2dd262ec4c811ba59eee96d54a7701930726bce18/installer-0.7.0-py3-none-any.whl",
        "05d1933f0a5ba7d8d6296bb6d5018e7c94fa473ceb10cf198a92ccea19c27b53",
    ),
    (
        "pypi__more_itertools",
        "https://files.pythonhosted.org/packages/2b/9f/7ba6f94fc1e9ac3d2b853fdff3035fb2fa5afbed898c4a72b8a020610594/more_itertools-10.7.0-py3-none-any.whl",
        "d43980384673cb07d2f7d2d918c616b30c659c089ee23953f601d6609c67510e",
    ),
    (
        "pypi__packaging",
        "https://files.pythonhosted.org/packages/20/12/38679034af332785aac8774540895e234f4d07f7545804097de4b666afd8/packaging-25.0-py3-none-any.whl",
        "29572ef2b1f17581046b3a2227d5c611fb25ec70ca1ba8554b24b0e69331a484",
    ),
    (
        "pypi__pep517",
        "https://files.pythonhosted.org/packages/25/6e/ca4a5434eb0e502210f591b97537d322546e4833dcb4d470a48c375c5540/pep517-0.13.1-py3-none-any.whl",
        "31b206f67165b3536dd577c5c3f1518e8fbaf38cbc57efff8369a392feff1721",
    ),
    (
        "pypi__pip",
        "https://files.pythonhosted.org/packages/e0/f0/8a2806114cd36e282823fd4d8e88e3b94dc943c2569c350d0c826a49db38/pip-25.1-py3-none-any.whl",
        "13b4aa0aaad055020a11bec8a1c2a70a2b2d080e12d89b962266029fff0a16ba",
    ),
    (
        "pypi__pip_tools",
        "https://files.pythonhosted.org/packages/0d/dc/38f4ce065e92c66f058ea7a368a9c5de4e702272b479c0992059f7693941/pip_tools-7.4.1-py3-none-any.whl",
        "4c690e5fbae2f21e87843e89c26191f0d9454f362d8acdbd695716493ec8b3a9",
    ),
    (
        "pypi__pyproject_hooks",
        "https://files.pythonhosted.org/packages/bd/24/12818598c362d7f300f18e74db45963dbcb85150324092410c8b49405e42/pyproject_hooks-1.2.0-py3-none-any.whl",
        "9e5c6bfa8dcc30091c74b0cf803c81fdd29d94f01992a7707bc97babb1141913",
    ),
    (
        "pypi__setuptools",
        "https://files.pythonhosted.org/packages/2a/8e/2ee81652472f3c11503d1780c41844a9a9656989b69c29811a4631e4aeb9/setuptools-80.0.1-py3-none-any.whl",
        "f4b49d457765b3aae7cbbeb1c71f6633a61b729408c2d1a837dae064cca82ef2",
    ),
    (
        "pypi__tomli",
        "https://files.pythonhosted.org/packages/c7/16/51ae563a8615d472fdbffc43a3f3d46588c264ac4f024f63f01283becfbb/tomli-2.2.1-cp311-cp311-macosx_11_0_arm64.whl",
        "023aa114dd824ade0100497eb2318602af309e5a55595f76b626d6d9f3b7b0a6",
    ),
    (
        "pypi__wheel",
        "https://files.pythonhosted.org/packages/0b/2c/87f3254fd8ffd29e4c02732eee68a83a1d3c346ae39bc6822dcbcb697f2b/wheel-0.45.1-py3-none-any.whl",
        "708e7481cc80179af0e556bbf0cc00b8444c7321e2700b8d8580231d13017248",
    ),
    (
        "pypi__zipp",
        "https://files.pythonhosted.org/packages/b7/1a/7e4798e9339adc931158c9d69ecc34f5e6791489d469f5e50ec15e35f458/zipp-3.21.0-py3-none-any.whl",
        "ac1bbe05fd2991f160ebce24ffbac5f6d11d83dc90891255885223d42b3cd931",
    ),
    # END: maintained by 'bazel run //tools/private/update_deps:update_pip_deps'
]

_GENERIC_WHEEL = """\
package(default_visibility = ["//visibility:public"])

load("@rules_python//python:py_library.bzl", "py_library")
load("@rules_python//python/private:glob_excludes.bzl", "glob_excludes")

py_library(
    name = "lib",
    srcs = glob(["**/*.py"]),
    data = glob(["**/*"], exclude=[
        # These entries include those put into user-installed dependencies by
        # data_exclude to avoid non-determinism.
        "**/*.py",
        "**/*.pyc",
        "**/*.pyc.*",  # During pyc creation, temp files named *.pyc.NNN are created
        "**/*.dist-info/RECORD",
        "BUILD",
        "WORKSPACE",
    ] + glob_excludes.version_dependent_exclusions()),
    # This makes this directory a top-level in the python import
    # search path for anything that depends on this.
    imports = ["."],
)
"""

# Collate all the repository names so they can be easily consumed
all_repo_names = [name for (name, _, _) in _RULE_DEPS]
record_files = {
    name: Label("@{}//:{}.dist-info/RECORD".format(
        name,
        url.rpartition("/")[-1].partition("-py3-none")[0],
    ))
    for (name, url, _) in _RULE_DEPS
}

def pypi_deps():
    """
    Fetch dependencies these rules depend on. Workspaces that use the pip_parse rule can call this.
    """
    for (name, url, sha256) in _RULE_DEPS:
        maybe(
            http_archive,
            name,
            url = url,
            sha256 = sha256,
            type = "zip",
            build_file_content = _GENERIC_WHEEL,
        )

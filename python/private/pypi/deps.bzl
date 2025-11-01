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
        "https://files.pythonhosted.org/packages/cb/8c/2b30c12155ad8de0cf641d76a8b396a16d2c36bc6d50b621a62b7c4567c1/build-1.3.0-py3-none-any.whl",
        "7145f0b5061ba90a1500d60bd1b13ca0a8a4cebdd0cc16ed8adf1c0e739f43b4",
    ),
    (
        "pypi__click",
        "https://files.pythonhosted.org/packages/db/d3/9dcc0f5797f070ec8edf30fbadfb200e71d9db6b84d211e3b2085a7589a0/click-8.3.0-py3-none-any.whl",
        "9b9f285302c6e3064f4330c05f05b81945b2a39544279343e6e7c5f27a9baddc",
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
        "https://files.pythonhosted.org/packages/a4/8e/469e5a4a2f5855992e425f3cb33804cc07bf18d48f2db061aec61ce50270/more_itertools-10.8.0-py3-none-any.whl",
        "52d4362373dcf7c52546bc4af9a86ee7c4579df9a8dc268be0a2f949d376cc9b",
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
        "https://files.pythonhosted.org/packages/44/3c/d717024885424591d5376220b5e836c2d5293ce2011523c9de23ff7bf068/pip-25.3-py3-none-any.whl",
        "9655943313a94722b7774661c21049070f6bbb0a1516bf02f7c8d5d9201514cd",
    ),
    (
        "pypi__pip_tools",
        "https://files.pythonhosted.org/packages/a1/27/76ffe2fa49527ef618950ca368f9d8dfdbb15efa088eb72b17066bbc1173/pip_tools-7.5.1-py3-none-any.whl",
        "f5ff803823529edc0e6e40c86b1aa7da7266fb1078093c8beea4e5b77877036a",
    ),
    (
        "pypi__pyproject_hooks",
        "https://files.pythonhosted.org/packages/bd/24/12818598c362d7f300f18e74db45963dbcb85150324092410c8b49405e42/pyproject_hooks-1.2.0-py3-none-any.whl",
        "9e5c6bfa8dcc30091c74b0cf803c81fdd29d94f01992a7707bc97babb1141913",
    ),
    (
        "pypi__setuptools",
        "https://files.pythonhosted.org/packages/a3/dc/17031897dae0efacfea57dfd3a82fdd2a2aeb58e0ff71b77b87e44edc772/setuptools-80.9.0-py3-none-any.whl",
        "062d34222ad13e0cc312a4c02d73f059e86a4acbfbdea8f8f76b28c99f306922",
    ),
    (
        "pypi__tomli",
        "https://files.pythonhosted.org/packages/89/da/75dfd804fc11e6612846758a23f13271b76d577e299592b4371a4ca4cd09/tomli-2.3.0-cp311-cp311-manylinux2014_x86_64.manylinux_2_17_x86_64.manylinux_2_28_x86_64.whl",
        "a0e285d2649b78c0d9027570d4da3425bdb49830a6156121360b3f8511ea3441",
    ),
    (
        "pypi__wheel",
        "https://files.pythonhosted.org/packages/0b/2c/87f3254fd8ffd29e4c02732eee68a83a1d3c346ae39bc6822dcbcb697f2b/wheel-0.45.1-py3-none-any.whl",
        "708e7481cc80179af0e556bbf0cc00b8444c7321e2700b8d8580231d13017248",
    ),
    (
        "pypi__zipp",
        "https://files.pythonhosted.org/packages/2e/54/647ade08bf0db230bfea292f893923872fd20be6ac6f53b2b936ba839d75/zipp-3.23.0-py3-none-any.whl",
        "071652d6115ed432f5ce1d34c336c0adfd6a884660d1e9712a256d3d3bd4b14e",
    ),
    # END: maintained by 'bazel run //tools/private/update_deps:update_pip_deps'
]

_GENERIC_WHEEL = """\
package(default_visibility = ["//visibility:public"])

load("@rules_python//python:py_library.bzl", "py_library")

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
    ]),
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

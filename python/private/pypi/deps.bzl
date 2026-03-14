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
        "https://files.pythonhosted.org/packages/c5/0d/84a4380f930db0010168e0aa7b7a8fed9ba1835a8fbb1472bc6d0201d529/build-1.4.0-py3-none-any.whl",
        "6a07c1b8eb6f2b311b96fcbdbce5dab5fe637ffda0fd83c9cac622e927501596",
    ),
    (
        "pypi__click",
        "https://files.pythonhosted.org/packages/98/78/01c019cdb5d6498122777c1a43056ebb3ebfeef2076d9d026bfe15583b2b/click-8.3.1-py3-none-any.whl",
        "981153a64e25f12d547d3426c367a4857371575ee7ad18df2a6183ab0545b2a6",
    ),
    (
        "pypi__colorama",
        "https://files.pythonhosted.org/packages/d1/d6/3965ed04c63042e047cb6a3e6ed1a63a35087b6a609aa3a15ed8ac56c221/colorama-0.4.6-py2.py3-none-any.whl",
        "4f1d9991f5acc0ca119f9d443620b77f9d6b33703e51011c16baf57afb285fc6",
    ),
    (
        "pypi__importlib_metadata",
        "https://files.pythonhosted.org/packages/fa/5e/f8e9a1d23b9c20a551a8a02ea3637b4642e22c2626e3a13a9a29cdea99eb/importlib_metadata-8.7.1-py3-none-any.whl",
        "5a1f80bf1daa489495071efbb095d75a634cf28a8bc299581244063b53176151",
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
        "https://files.pythonhosted.org/packages/b7/b9/c538f279a4e237a006a2c98387d081e9eb060d203d8ed34467cc0f0b9b53/packaging-26.0-py3-none-any.whl",
        "b36f1fef9334a5588b4166f8bcd26a14e521f2b55e6b9de3aaa80d3ff7a37529",
    ),
    (
        "pypi__pep517",
        "https://files.pythonhosted.org/packages/25/6e/ca4a5434eb0e502210f591b97537d322546e4833dcb4d470a48c375c5540/pep517-0.13.1-py3-none-any.whl",
        "31b206f67165b3536dd577c5c3f1518e8fbaf38cbc57efff8369a392feff1721",
    ),
    (
        "pypi__pip",
        "https://files.pythonhosted.org/packages/de/f0/c81e05b613866b76d2d1066490adf1a3dbc4ee9d9c839961c3fc8a6997af/pip-26.0.1-py3-none-any.whl",
        "bdb1b08f4274833d62c1aa29e20907365a2ceb950410df15fc9521bad440122b",
    ),
    (
        "pypi__pip_tools",
        "https://files.pythonhosted.org/packages/6e/74/59906d876c6cb1137f42a137164f2fe683b06283cde84bfcf7f5dd43970b/pip_tools-7.5.3-py3-none-any.whl",
        "3aac0c473240ae90db7213c033401f345b05197293ccbdd2704e52e7a783785e",
    ),
    (
        "pypi__pyproject_hooks",
        "https://files.pythonhosted.org/packages/bd/24/12818598c362d7f300f18e74db45963dbcb85150324092410c8b49405e42/pyproject_hooks-1.2.0-py3-none-any.whl",
        "9e5c6bfa8dcc30091c74b0cf803c81fdd29d94f01992a7707bc97babb1141913",
    ),
    (
        "pypi__setuptools",
        "https://files.pythonhosted.org/packages/e1/c6/76dc613121b793286a3f91621d7b75a2b493e0390ddca50f11993eadf192/setuptools-82.0.0-py3-none-any.whl",
        "70b18734b607bd1da571d097d236cfcfacaf01de45717d59e6e04b96877532e0",
    ),
    (
        "pypi__tomli",
        "https://files.pythonhosted.org/packages/23/d1/136eb2cb77520a31e1f64cbae9d33ec6df0d78bdf4160398e86eec8a8754/tomli-2.4.0-py3-none-any.whl",
        "1f776e7d669ebceb01dee46484485f43a4048746235e683bcdffacdf1fb4785a",
    ),
    (
        "pypi__wheel",
        "https://files.pythonhosted.org/packages/87/22/b76d483683216dde3d67cba61fb2444be8d5be289bf628c13fc0fd90e5f9/wheel-0.46.3-py3-none-any.whl",
        "4b399d56c9d9338230118d705d9737a2a468ccca63d5e813e2a4fc7815d8bc4d",
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

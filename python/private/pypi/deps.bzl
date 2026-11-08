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
    # START: maintained by 'bazel run //dev/update_deps:update_pip_deps'
    (
        "pypi__build",
        "https://files.pythonhosted.org/packages/ad/9b/9fb3585dabcd73a1b2a6267f63f62649347c9e6d072c9fde365b105abb2c/build-1.6.1-py3-none-any.whl",
        "ecd351a4be9d35a9eaaba244a7687143c9c7d4aea6ac964e7e7ddab20cbcf4e7",
    ),
    (
        "pypi__click",
        "https://files.pythonhosted.org/packages/58/50/6c0d534c5f134586a8e1ba4e330569e32f057e33372ae556463212fb4cd3/click-8.5.0-py3-none-any.whl",
        "255bc9599cf7748b4b1a446ccc735421bd08a2ae529a8b88597d3de5664ee360",
    ),
    (
        "pypi__colorama",
        "https://files.pythonhosted.org/packages/d1/d6/3965ed04c63042e047cb6a3e6ed1a63a35087b6a609aa3a15ed8ac56c221/colorama-0.4.6-py2.py3-none-any.whl",
        "4f1d9991f5acc0ca119f9d443620b77f9d6b33703e51011c16baf57afb285fc6",
    ),
    (
        "pypi__importlib_metadata",
        "https://files.pythonhosted.org/packages/b3/55/ecca97ae19075f1fac62def77731e7f535e6c1fb8f92ff08160c5e6dade8/importlib_metadata-9.0.1-py3-none-any.whl",
        "bba5600596a7e21f3eef53281cf28d6a5195634d2f2b78ff9501a3272c6eaab0",
    ),
    (
        "pypi__installer",
        "https://files.pythonhosted.org/packages/d7/7a/63547a792a12148882205d79e07644091d5b7690f40c2bb9d41452a8bdc2/installer-1.1.0-py3-none-any.whl",
        "f55f5728ff61d3dd54dbc5a397cf3f7307cb64b180c20b72afbebf01c9e2c8a0",
    ),
    (
        "pypi__more_itertools",
        "https://files.pythonhosted.org/packages/e8/3d/1087453384dbde46a8c7f9356eead2c58be8a7bf156bca40243377c85715/more_itertools-11.1.0-py3-none-any.whl",
        "4b65538ae22f6fed0ce4874efd317463a7489796a0939fa66824dd542125a192",
    ),
    (
        "pypi__packaging",
        "https://files.pythonhosted.org/packages/63/34/ba1c580383c9eada3711951fef0795c80b829a078d72188184bcab9dd527/packaging-26.3-py3-none-any.whl",
        "d7193f7c8e4e93f444fde0262bf90af30e16fa0ad0ad44cb553c87339b23cd1c",
    ),
    (
        "pypi__pep517",
        "https://files.pythonhosted.org/packages/25/6e/ca4a5434eb0e502210f591b97537d322546e4833dcb4d470a48c375c5540/pep517-0.13.1-py3-none-any.whl",
        "31b206f67165b3536dd577c5c3f1518e8fbaf38cbc57efff8369a392feff1721",
    ),
    (
        "pypi__pip",
        "https://files.pythonhosted.org/packages/3f/06/3e4420302363fbb71be3c7f35ce042f54bfca330e3e66b3a2e3c4cca579f/pip-26.2.2-py3-none-any.whl",
        "fd7f4dfa8190e014013b9f08f3e973f4e4c26ffd179a204895533a7254813a70",
    ),
    (
        "pypi__pip_tools",
        "https://files.pythonhosted.org/packages/4b/68/f3bd09c53ed3159bb1349e1d5859ad1ea7755b8e4cd50174290e9e8cbb47/pip_tools-7.6.2-py3-none-any.whl",
        "f37eb4b736859c2c30230e50977312c61918b7ef931071ff7811fd067715c25f",
    ),
    (
        "pypi__pyproject_hooks",
        "https://files.pythonhosted.org/packages/85/11/044d1ae1b4ec0d7af88ee5bc91e081be1022533032b906a7bdabdbb60977/pyproject_hooks-1.3.3-py3-none-any.whl",
        "5fc53fdac9f7bd63fbcdc868fb5f90b4784d78a53a3d3388cd738b807441a20b",
    ),
    (
        "pypi__setuptools",
        "https://files.pythonhosted.org/packages/ef/55/6dc6d6bb953bdfc52519a0059592c52b6e3b8ad51cf8256dffceb55b0610/setuptools-84.2.1-py3-none-any.whl",
        "ca140b45d5325a9478f880e351484f62fef15f336462e449ca0c03c873d589c2",
    ),
    (
        "pypi__tomli",
        "https://files.pythonhosted.org/packages/60/3f/3e3f8fd0919249b0200c80fbc4f9a1e70be19f9883da71dfb7f8b9ab8aca/tomli-2.5.0-py3-none-any.whl",
        "32a7b79ac57a2e83670ce329ccf675798bc5a2094783a63676866b70503f2e2b",
    ),
    (
        "pypi__typing_extensions",
        "https://files.pythonhosted.org/packages/49/d3/b8441a820a491ddfc024b0b0cf0393375b75ea13866d9c66727e54c2fc80/typing_extensions-4.16.0-py3-none-any.whl",
        "481caa481374e813c1b176ada14e97f1f67a4539ce9cfeb3f350d78d6370c2e8",
    ),
    (
        "pypi__wheel",
        "https://files.pythonhosted.org/packages/2e/29/69cfbb602cd91690c55d38ba9fe53e6a7e76a6fa647bf38f19c138d25449/wheel-0.48.0-py3-none-any.whl",
        "3217dcc807155e45db462d7ef2431f5ddda0d7273b700d05a67b271ceb1287ab",
    ),
    (
        "pypi__zipp",
        "https://files.pythonhosted.org/packages/b8/44/7bd2007260da11cccca29ba2d4c345f1287aa663db38ee7cefeabf6386a5/zipp-4.1.2-py3-none-any.whl",
        "b30cb6cd253122169c47de245ca24a86bac2a5d3802ba15bf7ba6414eb9e144d",
    ),
    # END: maintained by 'bazel run //dev/update_deps:update_pip_deps'
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

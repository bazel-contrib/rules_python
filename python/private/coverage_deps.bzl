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

"""Dependencies for coverage.py used by the hermetic toolchain.
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("//python/private:version_label.bzl", "version_label")

# START: maintained by 'bazel run //tools/private/update_deps:update_coverage_deps <version>'
_coverage_deps = {
    "cp310": {
        "aarch64-apple-darwin": (
            "https://files.pythonhosted.org/packages/03/94/952d30f180b1a916c11a56f5c22d3535e943aa22430e9e3322447e520e1c/coverage-7.10.7-cp310-cp310-macosx_11_0_arm64.whl",
            "e201e015644e207139f7e2351980feb7040e6f4b2c2978892f3e3789d1c125e5",
        ),
        "aarch64-unknown-linux-gnu": (
            "https://files.pythonhosted.org/packages/60/83/5c283cff3d41285f8eab897651585db908a909c572bdc014bcfaf8a8b6ae/coverage-7.10.7-cp310-cp310-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
            "6be8ed3039ae7f7ac5ce058c308484787c86e8437e72b30bf5e88b8ea10f3c87",
        ),
        "x86_64-apple-darwin": (
            "https://files.pythonhosted.org/packages/e5/6c/3a3f7a46888e69d18abe3ccc6fe4cb16cccb1e6a2f99698931dafca489e6/coverage-7.10.7-cp310-cp310-macosx_10_9_x86_64.whl",
            "fc04cc7a3db33664e0c2d10eb8990ff6b3536f6842c9590ae8da4c614b9ed05a",
        ),
        "x86_64-unknown-linux-gnu": (
            "https://files.pythonhosted.org/packages/19/20/d0384ac06a6f908783d9b6aa6135e41b093971499ec488e47279f5b846e6/coverage-7.10.7-cp310-cp310-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
            "8421e088bc051361b01c4b3a50fd39a4b9133079a2229978d9d30511fd05231b",
        ),
    },
    "cp311": {
        "aarch64-apple-darwin": (
            "https://files.pythonhosted.org/packages/54/f0/514dcf4b4e3698b9a9077f084429681bf3aad2b4a72578f89d7f643eb506/coverage-7.10.7-cp311-cp311-macosx_11_0_arm64.whl",
            "65646bb0359386e07639c367a22cf9b5bf6304e8630b565d0626e2bdf329227a",
        ),
        "aarch64-unknown-linux-gnu": (
            "https://files.pythonhosted.org/packages/a5/b6/bf054de41ec948b151ae2b79a55c107f5760979538f5fb80c195f2517718/coverage-7.10.7-cp311-cp311-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
            "4da86b6d62a496e908ac2898243920c7992499c1712ff7c2b6d837cc69d9467e",
        ),
        "x86_64-apple-darwin": (
            "https://files.pythonhosted.org/packages/d2/5d/c1a17867b0456f2e9ce2d8d4708a4c3a089947d0bec9c66cdf60c9e7739f/coverage-7.10.7-cp311-cp311-macosx_10_9_x86_64.whl",
            "a609f9c93113be646f44c2a0256d6ea375ad047005d7f57a5c15f614dc1b2f59",
        ),
        "x86_64-unknown-linux-gnu": (
            "https://files.pythonhosted.org/packages/b0/ef/bd8e719c2f7417ba03239052e099b76ea1130ac0cbb183ee1fcaa58aaff3/coverage-7.10.7-cp311-cp311-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
            "35f5e3f9e455bb17831876048355dca0f758b6df22f49258cb5a91da23ef437d",
        ),
    },
    "cp312": {
        "aarch64-apple-darwin": (
            "https://files.pythonhosted.org/packages/37/66/593f9be12fc19fb36711f19a5371af79a718537204d16ea1d36f16bd78d2/coverage-7.10.7-cp312-cp312-macosx_11_0_arm64.whl",
            "18afb24843cbc175687225cab1138c95d262337f5473512010e46831aa0c2973",
        ),
        "aarch64-unknown-linux-gnu": (
            "https://files.pythonhosted.org/packages/98/2e/2dda59afd6103b342e096f246ebc5f87a3363b5412609946c120f4e7750d/coverage-7.10.7-cp312-cp312-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
            "c41e71c9cfb854789dee6fc51e46743a6d138b1803fab6cb860af43265b42ea6",
        ),
        "x86_64-apple-darwin": (
            "https://files.pythonhosted.org/packages/13/e4/eb12450f71b542a53972d19117ea5a5cea1cab3ac9e31b0b5d498df1bd5a/coverage-7.10.7-cp312-cp312-macosx_10_13_x86_64.whl",
            "7bb3b9ddb87ef7725056572368040c32775036472d5a033679d1fa6c8dc08417",
        ),
        "x86_64-unknown-linux-gnu": (
            "https://files.pythonhosted.org/packages/a6/90/a64aaacab3b37a17aaedd83e8000142561a29eb262cede42d94a67f7556b/coverage-7.10.7-cp312-cp312-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
            "314f2c326ded3f4b09be11bc282eb2fc861184bc95748ae67b360ac962770be7",
        ),
    },
    "cp313": {
        "aarch64-apple-darwin": (
            "https://files.pythonhosted.org/packages/72/4f/732fff31c119bb73b35236dd333030f32c4bfe909f445b423e6c7594f9a2/coverage-7.10.7-cp313-cp313-macosx_11_0_arm64.whl",
            "73ab1601f84dc804f7812dc297e93cd99381162da39c47040a827d4e8dafe63b",
        ),
        "aarch64-apple-darwin-freethreaded": (
            "https://files.pythonhosted.org/packages/11/0b/91128e099035ece15da3445d9015e4b4153a6059403452d324cbb0a575fa/coverage-7.10.7-cp313-cp313t-macosx_11_0_arm64.whl",
            "dd5e856ebb7bfb7672b0086846db5afb4567a7b9714b8a0ebafd211ec7ce6a15",
        ),
        "aarch64-unknown-linux-gnu": (
            "https://files.pythonhosted.org/packages/b1/20/b6ea4f69bbb52dac0aebd62157ba6a9dddbfe664f5af8122dac296c3ee15/coverage-7.10.7-cp313-cp313-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
            "c79124f70465a150e89340de5963f936ee97097d2ef76c869708c4248c63ca49",
        ),
        "aarch64-unknown-linux-gnu-freethreaded": (
            "https://files.pythonhosted.org/packages/f7/08/16bee2c433e60913c610ea200b276e8eeef084b0d200bdcff69920bd5828/coverage-7.10.7-cp313-cp313t-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
            "83082a57783239717ceb0ad584de3c69cf581b2a95ed6bf81ea66034f00401c0",
        ),
        "x86_64-apple-darwin": (
            "https://files.pythonhosted.org/packages/9a/94/b765c1abcb613d103b64fcf10395f54d69b0ef8be6a0dd9c524384892cc7/coverage-7.10.7-cp313-cp313-macosx_10_13_x86_64.whl",
            "981a651f543f2854abd3b5fcb3263aac581b18209be49863ba575de6edf4c14d",
        ),
        "x86_64-apple-darwin-freethreaded": (
            "https://files.pythonhosted.org/packages/bb/22/e04514bf2a735d8b0add31d2b4ab636fc02370730787c576bb995390d2d5/coverage-7.10.7-cp313-cp313t-macosx_10_13_x86_64.whl",
            "a0ec07fd264d0745ee396b666d47cef20875f4ff2375d7c4f58235886cc1ef0c",
        ),
        "x86_64-unknown-linux-gnu": (
            "https://files.pythonhosted.org/packages/a2/77/8c6d22bf61921a59bce5471c2f1f7ac30cd4ac50aadde72b8c48d5727902/coverage-7.10.7-cp313-cp313-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
            "10b6ba00ab1132a0ce4428ff68cf50a25efd6840a42cdf4239c9b99aad83be8b",
        ),
        "x86_64-unknown-linux-gnu-freethreaded": (
            "https://files.pythonhosted.org/packages/5d/22/9b8d458c2881b22df3db5bb3e7369e63d527d986decb6c11a591ba2364f7/coverage-7.10.7-cp313-cp313t-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
            "1ef2319dd15a0b009667301a3f84452a4dc6fddfd06b0c5c53ea472d3989fbf0",
        ),
    },
    "cp314": {
        "aarch64-apple-darwin": (
            "https://files.pythonhosted.org/packages/f0/89/673f6514b0961d1f0e20ddc242e9342f6da21eaba3489901b565c0689f34/coverage-7.10.7-cp314-cp314-macosx_11_0_arm64.whl",
            "212f8f2e0612778f09c55dd4872cb1f64a1f2b074393d139278ce902064d5b32",
        ),
        "aarch64-apple-darwin-freethreaded": (
            "https://files.pythonhosted.org/packages/f5/6f/f58d46f33db9f2e3647b2d0764704548c184e6f5e014bef528b7f979ef84/coverage-7.10.7-cp314-cp314t-macosx_11_0_arm64.whl",
            "9fa6e4dd51fe15d8738708a973470f67a855ca50002294852e9571cdbd9433f2",
        ),
        "aarch64-unknown-linux-gnu": (
            "https://files.pythonhosted.org/packages/ff/49/07f00db9ac6478e4358165a08fb41b469a1b053212e8a00cb02f0d27a05f/coverage-7.10.7-cp314-cp314-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
            "813922f35bd800dca9994c5971883cbc0d291128a5de6b167c7aa697fcf59360",
        ),
        "aarch64-unknown-linux-gnu-freethreaded": (
            "https://files.pythonhosted.org/packages/84/fd/193a8fb132acfc0a901f72020e54be5e48021e1575bb327d8ee1097a28fd/coverage-7.10.7-cp314-cp314t-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
            "6e16e07d85ca0cf8bafe5f5d23a0b850064e8e945d5677492b06bbe6f09cc699",
        ),
        "x86_64-apple-darwin": (
            "https://files.pythonhosted.org/packages/23/9c/5844ab4ca6a4dd97a1850e030a15ec7d292b5c5cb93082979225126e35dd/coverage-7.10.7-cp314-cp314-macosx_10_13_x86_64.whl",
            "b06f260b16ead11643a5a9f955bd4b5fd76c1a4c6796aeade8520095b75de520",
        ),
        "x86_64-apple-darwin-freethreaded": (
            "https://files.pythonhosted.org/packages/62/09/9a5608d319fa3eba7a2019addeacb8c746fb50872b57a724c9f79f146969/coverage-7.10.7-cp314-cp314t-macosx_10_13_x86_64.whl",
            "a62c6ef0d50e6de320c270ff91d9dd0a05e7250cac2a800b7784bae474506e63",
        ),
        "x86_64-unknown-linux-gnu": (
            "https://files.pythonhosted.org/packages/82/62/14ed6546d0207e6eda876434e3e8475a3e9adbe32110ce896c9e0c06bb9a/coverage-7.10.7-cp314-cp314-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
            "bb45474711ba385c46a0bfe696c695a929ae69ac636cda8f532be9e8c93d720a",
        ),
        "x86_64-unknown-linux-gnu-freethreaded": (
            "https://files.pythonhosted.org/packages/0f/48/71a8abe9c1ad7e97548835e3cc1adbf361e743e9d60310c5f75c9e7bf847/coverage-7.10.7-cp314-cp314t-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
            "affef7c76a9ef259187ef31599a9260330e0335a3011732c4b9effa01e1cd6e0",
        ),
    },
    "cp39": {
        "aarch64-apple-darwin": (
            "https://files.pythonhosted.org/packages/52/2f/b9f9daa39b80ece0b9548bbb723381e29bc664822d9a12c2135f8922c22b/coverage-7.10.7-cp39-cp39-macosx_11_0_arm64.whl",
            "bc91b314cef27742da486d6839b677b3f2793dfe52b51bbbb7cf736d5c29281c",
        ),
        "aarch64-unknown-linux-gnu": (
            "https://files.pythonhosted.org/packages/6a/92/1c1c5a9e8677ce56d42b97bdaca337b2d4d9ebe703d8c174ede52dbabd5f/coverage-7.10.7-cp39-cp39-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
            "c7315339eae3b24c2d2fa1ed7d7a38654cba34a13ef19fbcb9425da46d3dc594",
        ),
        "x86_64-apple-darwin": (
            "https://files.pythonhosted.org/packages/a3/ad/d1c25053764b4c42eb294aae92ab617d2e4f803397f9c7c8295caa77a260/coverage-7.10.7-cp39-cp39-macosx_10_9_x86_64.whl",
            "fff7b9c3f19957020cac546c70025331113d2e61537f6e2441bc7657913de7d3",
        ),
        "x86_64-unknown-linux-gnu": (
            "https://files.pythonhosted.org/packages/b0/49/8a070782ce7e6b94ff6a0b6d7c65ba6bc3091d92a92cef4cd4eb0767965c/coverage-7.10.7-cp39-cp39-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
            "2af88deffcc8a4d5974cf2d502251bc3b2db8461f0b66d80a449c33757aa9f40",
        ),
    },
}
# END: maintained by 'bazel run //tools/private/update_deps:update_coverage_deps <version>'

_coverage_patch = Label("//python/private:coverage.patch")

def coverage_dep(name, python_version, platform, visibility):
    """Register a single coverage dependency based on the python version and platform.

    Args:
        name: The name of the registered repository.
        python_version: The full python version.
        platform: The platform, which can be found in //python:versions.bzl PLATFORMS dict.
        visibility: The visibility of the coverage tool.

    Returns:
        The label of the coverage tool if the platform is supported, otherwise - None.
    """
    if "windows" in platform:
        # NOTE @aignas 2023-01-19: currently we do not support windows as the
        # upstream coverage wrapper is written in shell. Do not log any warning
        # for now as it is not actionable.
        return None

    abi = "cp" + version_label(python_version)
    url, sha256 = _coverage_deps.get(abi, {}).get(platform, (None, ""))

    if url == None:
        # Some wheels are not present for some builds, so let's silently ignore those.
        return None

    maybe(
        http_archive,
        name = name,
        build_file_content = """
filegroup(
    name = "coverage",
    srcs = ["coverage/__main__.py"],
    data = glob(["coverage/*.py", "coverage/**/*.py", "coverage/*.so"]),
    visibility = {visibility},
)
    """.format(
            visibility = visibility,
        ),
        patch_args = ["-p1"],
        patches = [_coverage_patch],
        sha256 = sha256,
        type = "zip",
        urls = [url],
    )

    return "@{name}//:coverage".format(name = name)

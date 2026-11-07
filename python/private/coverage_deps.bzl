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
load("//python/private:repo_utils.bzl", "repo_utils")
load("//python/private/pypi:pep508_evaluate.bzl", "evaluate")
load("//python/private/pypi:python_toolchain_platform.bzl", "python_toolchain_platform")
load("//python/private/pypi:select_whl.bzl", "select_whl")

# The wheels below are generated from the `//dev/update_deps/coverage:uv.lock`
# file, see `//dev/update_deps/coverage:pyproject.toml` for how to update them.
#
# Newer coverage versions do not support older python versions, so each version
# has a `python_version` marker for when it should be used.
# START: maintained by 'bazel run //dev/update_deps:update_coverage_deps <version>'
_coverage_wheels = [
    struct(
        url = "https://files.pythonhosted.org/packages/e5/6c/3a3f7a46888e69d18abe3ccc6fe4cb16cccb1e6a2f99698931dafca489e6/coverage-7.10.7-cp310-cp310-macosx_10_9_x86_64.whl",
        hash = "sha256:fc04cc7a3db33664e0c2d10eb8990ff6b3536f6842c9590ae8da4c614b9ed05a",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/03/94/952d30f180b1a916c11a56f5c22d3535e943aa22430e9e3322447e520e1c/coverage-7.10.7-cp310-cp310-macosx_11_0_arm64.whl",
        hash = "sha256:e201e015644e207139f7e2351980feb7040e6f4b2c2978892f3e3789d1c125e5",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/50/2b/9e0cf8ded1e114bcd8b2fd42792b57f1c4e9e4ea1824cde2af93a67305be/coverage-7.10.7-cp310-cp310-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:240af60539987ced2c399809bd34f7c78e8abe0736af91c3d7d0e795df633d17",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/19/20/d0384ac06a6f908783d9b6aa6135e41b093971499ec488e47279f5b846e6/coverage-7.10.7-cp310-cp310-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:8421e088bc051361b01c4b3a50fd39a4b9133079a2229978d9d30511fd05231b",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/60/83/5c283cff3d41285f8eab897651585db908a909c572bdc014bcfaf8a8b6ae/coverage-7.10.7-cp310-cp310-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:6be8ed3039ae7f7ac5ce058c308484787c86e8437e72b30bf5e88b8ea10f3c87",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/60/22/02eb98fdc5ff79f423e990d877693e5310ae1eab6cb20ae0b0b9ac45b23b/coverage-7.10.7-cp310-cp310-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:e28299d9f2e889e6d51b1f043f58d5f997c373cc12e6403b90df95b8b047c13e",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/b4/bc/25c83bcf3ad141b32cd7dc45485ef3c01a776ca3aa8ef0a93e77e8b5bc43/coverage-7.10.7-cp310-cp310-musllinux_1_2_aarch64.whl",
        hash = "sha256:c4e16bd7761c5e454f4efd36f345286d6f7c5fa111623c355691e2755cae3b9e",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/3c/b7/95574702888b58c0928a6e982038c596f9c34d52c5e5107f1eef729399b5/coverage-7.10.7-cp310-cp310-musllinux_1_2_i686.whl",
        hash = "sha256:b1c81d0e5e160651879755c9c675b974276f135558cf4ba79fee7b8413a515df",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/47/b6/40095c185f235e085df0e0b158f6bd68cc6e1d80ba6c7721dc81d97ec318/coverage-7.10.7-cp310-cp310-musllinux_1_2_riscv64.whl",
        hash = "sha256:606cc265adc9aaedcc84f1f064f0e8736bc45814f15a357e30fca7ecc01504e0",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/c8/50/4aea0556da7a4b93ec9168420d170b55e2eb50ae21b25062513d020c6861/coverage-7.10.7-cp310-cp310-musllinux_1_2_x86_64.whl",
        hash = "sha256:10b24412692df990dbc34f8fb1b6b13d236ace9dfdd68df5b28c2e39cafbba13",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/6a/28/ea1a84a60828177ae3b100cb6723838523369a44ec5742313ed7db3da160/coverage-7.10.7-cp310-cp310-win32.whl",
        hash = "sha256:b51dcd060f18c19290d9b8a9dd1e0181538df2ce0717f562fff6cf74d9fc0b5b",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/fc/1a/a81d46bbeb3c3fd97b9602ebaa411e076219a150489bcc2c025f151bd52d/coverage-7.10.7-cp310-cp310-win_amd64.whl",
        hash = "sha256:3a622ac801b17198020f09af3eaf45666b344a0d69fc2a6ffe2ea83aeef1d807",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/d2/5d/c1a17867b0456f2e9ce2d8d4708a4c3a089947d0bec9c66cdf60c9e7739f/coverage-7.10.7-cp311-cp311-macosx_10_9_x86_64.whl",
        hash = "sha256:a609f9c93113be646f44c2a0256d6ea375ad047005d7f57a5c15f614dc1b2f59",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/54/f0/514dcf4b4e3698b9a9077f084429681bf3aad2b4a72578f89d7f643eb506/coverage-7.10.7-cp311-cp311-macosx_11_0_arm64.whl",
        hash = "sha256:65646bb0359386e07639c367a22cf9b5bf6304e8630b565d0626e2bdf329227a",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/20/f6/9626b81d17e2a4b25c63ac1b425ff307ecdeef03d67c9a147673ae40dc36/coverage-7.10.7-cp311-cp311-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:5f33166f0dfcce728191f520bd2692914ec70fac2713f6bf3ce59c3deacb4699",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/b0/ef/bd8e719c2f7417ba03239052e099b76ea1130ac0cbb183ee1fcaa58aaff3/coverage-7.10.7-cp311-cp311-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:35f5e3f9e455bb17831876048355dca0f758b6df22f49258cb5a91da23ef437d",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a5/b6/bf054de41ec948b151ae2b79a55c107f5760979538f5fb80c195f2517718/coverage-7.10.7-cp311-cp311-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:4da86b6d62a496e908ac2898243920c7992499c1712ff7c2b6d837cc69d9467e",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/0f/e5/3860756aa6f9318227443c6ce4ed7bf9e70bb7f1447a0353f45ac5c7974b/coverage-7.10.7-cp311-cp311-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:6b8b09c1fad947c84bbbc95eca841350fad9cbfa5a2d7ca88ac9f8d836c92e23",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/26/0f/bd08bd042854f7fd07b45808927ebcce99a7ed0f2f412d11629883517ac2/coverage-7.10.7-cp311-cp311-musllinux_1_2_aarch64.whl",
        hash = "sha256:4376538f36b533b46f8971d3a3e63464f2c7905c9800db97361c43a2b14792ab",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/8e/a7/4777b14de4abcc2e80c6b1d430f5d51eb18ed1d75fca56cbce5f2db9b36e/coverage-7.10.7-cp311-cp311-musllinux_1_2_i686.whl",
        hash = "sha256:121da30abb574f6ce6ae09840dae322bef734480ceafe410117627aa54f76d82",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/34/72/17d082b00b53cd45679bad682fac058b87f011fd8b9fe31d77f5f8d3a4e4/coverage-7.10.7-cp311-cp311-musllinux_1_2_riscv64.whl",
        hash = "sha256:88127d40df529336a9836870436fc2751c339fbaed3a836d42c93f3e4bd1d0a2",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/81/7a/92367572eb5bdd6a84bfa278cc7e97db192f9f45b28c94a9ca1a921c3577/coverage-7.10.7-cp311-cp311-musllinux_1_2_x86_64.whl",
        hash = "sha256:ba58bbcd1b72f136080c0bccc2400d66cc6115f3f906c499013d065ac33a4b61",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/2f/88/a23cc185f6a805dfc4fdf14a94016835eeb85e22ac3a0e66d5e89acd6462/coverage-7.10.7-cp311-cp311-win32.whl",
        hash = "sha256:972b9e3a4094b053a4e46832b4bc829fc8a8d347160eb39d03f1690316a99c14",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/fe/ef/0b510a399dfca17cec7bc2f05ad8bd78cf55f15c8bc9a73ab20c5c913c2e/coverage-7.10.7-cp311-cp311-win_amd64.whl",
        hash = "sha256:a7b55a944a7f43892e28ad4bc0561dfd5f0d73e605d1aa5c3c976b52aea121d2",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/51/7f/023657f301a276e4ba1850f82749bc136f5a7e8768060c2e5d9744a22951/coverage-7.10.7-cp311-cp311-win_arm64.whl",
        hash = "sha256:736f227fb490f03c6488f9b6d45855f8e0fd749c007f9303ad30efab0e73c05a",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/13/e4/eb12450f71b542a53972d19117ea5a5cea1cab3ac9e31b0b5d498df1bd5a/coverage-7.10.7-cp312-cp312-macosx_10_13_x86_64.whl",
        hash = "sha256:7bb3b9ddb87ef7725056572368040c32775036472d5a033679d1fa6c8dc08417",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/37/66/593f9be12fc19fb36711f19a5371af79a718537204d16ea1d36f16bd78d2/coverage-7.10.7-cp312-cp312-macosx_11_0_arm64.whl",
        hash = "sha256:18afb24843cbc175687225cab1138c95d262337f5473512010e46831aa0c2973",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/66/80/4c49f7ae09cafdacc73fbc30949ffe77359635c168f4e9ff33c9ebb07838/coverage-7.10.7-cp312-cp312-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:399a0b6347bcd3822be369392932884b8216d0944049ae22925631a9b3d4ba4c",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a6/90/a64aaacab3b37a17aaedd83e8000142561a29eb262cede42d94a67f7556b/coverage-7.10.7-cp312-cp312-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:314f2c326ded3f4b09be11bc282eb2fc861184bc95748ae67b360ac962770be7",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/98/2e/2dda59afd6103b342e096f246ebc5f87a3363b5412609946c120f4e7750d/coverage-7.10.7-cp312-cp312-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:c41e71c9cfb854789dee6fc51e46743a6d138b1803fab6cb860af43265b42ea6",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/53/dc/8d8119c9051d50f3119bb4a75f29f1e4a6ab9415cd1fa8bf22fcc3fb3b5f/coverage-7.10.7-cp312-cp312-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:bc01f57ca26269c2c706e838f6422e2a8788e41b3e3c65e2f41148212e57cd59",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/98/b3/edaff9c5d79ee4d4b6d3fe046f2b1d799850425695b789d491a64225d493/coverage-7.10.7-cp312-cp312-musllinux_1_2_aarch64.whl",
        hash = "sha256:a6442c59a8ac8b85812ce33bc4d05bde3fb22321fa8294e2a5b487c3505f611b",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/11/25/9a0728564bb05863f7e513e5a594fe5ffef091b325437f5430e8cfb0d530/coverage-7.10.7-cp312-cp312-musllinux_1_2_i686.whl",
        hash = "sha256:78a384e49f46b80fb4c901d52d92abe098e78768ed829c673fbb53c498bef73a",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/e0/fd/ca2650443bfbef5b0e74373aac4df67b08180d2f184b482c41499668e258/coverage-7.10.7-cp312-cp312-musllinux_1_2_riscv64.whl",
        hash = "sha256:5e1e9802121405ede4b0133aa4340ad8186a1d2526de5b7c3eca519db7bb89fb",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/24/79/f692f125fb4299b6f963b0745124998ebb8e73ecdfce4ceceb06a8c6bec5/coverage-7.10.7-cp312-cp312-musllinux_1_2_x86_64.whl",
        hash = "sha256:d41213ea25a86f69efd1575073d34ea11aabe075604ddf3d148ecfec9e1e96a1",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/5e/75/61b9bbd6c7d24d896bfeec57acba78e0f8deac68e6baf2d4804f7aae1f88/coverage-7.10.7-cp312-cp312-win32.whl",
        hash = "sha256:77eb4c747061a6af8d0f7bdb31f1e108d172762ef579166ec84542f711d90256",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ca/f3/3bf7905288b45b075918d372498f1cf845b5b579b723c8fd17168018d5f5/coverage-7.10.7-cp312-cp312-win_amd64.whl",
        hash = "sha256:f51328ffe987aecf6d09f3cd9d979face89a617eacdaea43e7b3080777f647ba",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/5c/44/3e32dbe933979d05cf2dac5e697c8599cfe038aaf51223ab901e208d5a62/coverage-7.10.7-cp312-cp312-win_arm64.whl",
        hash = "sha256:bda5e34f8a75721c96085903c6f2197dc398c20ffd98df33f866a9c8fd95f4bf",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/9a/94/b765c1abcb613d103b64fcf10395f54d69b0ef8be6a0dd9c524384892cc7/coverage-7.10.7-cp313-cp313-macosx_10_13_x86_64.whl",
        hash = "sha256:981a651f543f2854abd3b5fcb3263aac581b18209be49863ba575de6edf4c14d",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/72/4f/732fff31c119bb73b35236dd333030f32c4bfe909f445b423e6c7594f9a2/coverage-7.10.7-cp313-cp313-macosx_11_0_arm64.whl",
        hash = "sha256:73ab1601f84dc804f7812dc297e93cd99381162da39c47040a827d4e8dafe63b",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/87/02/ae7e0af4b674be47566707777db1aa375474f02a1d64b9323e5813a6cdd5/coverage-7.10.7-cp313-cp313-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:a8b6f03672aa6734e700bbcd65ff050fd19cddfec4b031cc8cf1c6967de5a68e",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a2/77/8c6d22bf61921a59bce5471c2f1f7ac30cd4ac50aadde72b8c48d5727902/coverage-7.10.7-cp313-cp313-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:10b6ba00ab1132a0ce4428ff68cf50a25efd6840a42cdf4239c9b99aad83be8b",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/b1/20/b6ea4f69bbb52dac0aebd62157ba6a9dddbfe664f5af8122dac296c3ee15/coverage-7.10.7-cp313-cp313-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:c79124f70465a150e89340de5963f936ee97097d2ef76c869708c4248c63ca49",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/f9/28/4831523ba483a7f90f7b259d2018fef02cb4d5b90bc7c1505d6e5a84883c/coverage-7.10.7-cp313-cp313-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:69212fbccdbd5b0e39eac4067e20a4a5256609e209547d86f740d68ad4f04911",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a7/9f/4331142bc98c10ca6436d2d620c3e165f31e6c58d43479985afce6f3191c/coverage-7.10.7-cp313-cp313-musllinux_1_2_aarch64.whl",
        hash = "sha256:7ea7c6c9d0d286d04ed3541747e6597cbe4971f22648b68248f7ddcd329207f0",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ce/60/bda83b96602036b77ecf34e6393a3836365481b69f7ed7079ab85048202b/coverage-7.10.7-cp313-cp313-musllinux_1_2_i686.whl",
        hash = "sha256:b9be91986841a75042b3e3243d0b3cb0b2434252b977baaf0cd56e960fe1e46f",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/5f/af/152633ff35b2af63977edd835d8e6430f0caef27d171edf2fc76c270ef31/coverage-7.10.7-cp313-cp313-musllinux_1_2_riscv64.whl",
        hash = "sha256:b281d5eca50189325cfe1f365fafade89b14b4a78d9b40b05ddd1fc7d2a10a9c",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/9d/71/d92105d122bd21cebba877228990e1646d862e34a98bb3374d3fece5a794/coverage-7.10.7-cp313-cp313-musllinux_1_2_x86_64.whl",
        hash = "sha256:99e4aa63097ab1118e75a848a28e40d68b08a5e19ce587891ab7fd04475e780f",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a2/9e/9fdb08f4bf476c912f0c3ca292e019aab6712c93c9344a1653986c3fd305/coverage-7.10.7-cp313-cp313-win32.whl",
        hash = "sha256:dc7c389dce432500273eaf48f410b37886be9208b2dd5710aaf7c57fd442c698",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/b1/b1/a75fd25df44eab52d1931e89980d1ada46824c7a3210be0d3c88a44aaa99/coverage-7.10.7-cp313-cp313-win_amd64.whl",
        hash = "sha256:cac0fdca17b036af3881a9d2729a850b76553f3f716ccb0360ad4dbc06b3b843",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/14/3a/d720d7c989562a6e9a14b2c9f5f2876bdb38e9367126d118495b89c99c37/coverage-7.10.7-cp313-cp313-win_arm64.whl",
        hash = "sha256:4b6f236edf6e2f9ae8fcd1332da4e791c1b6ba0dc16a2dc94590ceccb482e546",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/bb/22/e04514bf2a735d8b0add31d2b4ab636fc02370730787c576bb995390d2d5/coverage-7.10.7-cp313-cp313t-macosx_10_13_x86_64.whl",
        hash = "sha256:a0ec07fd264d0745ee396b666d47cef20875f4ff2375d7c4f58235886cc1ef0c",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/11/0b/91128e099035ece15da3445d9015e4b4153a6059403452d324cbb0a575fa/coverage-7.10.7-cp313-cp313t-macosx_11_0_arm64.whl",
        hash = "sha256:dd5e856ebb7bfb7672b0086846db5afb4567a7b9714b8a0ebafd211ec7ce6a15",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/8b/51/66420081e72801536a091a0c8f8c1f88a5c4bf7b9b1bdc6222c7afe6dc9b/coverage-7.10.7-cp313-cp313t-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:f57b2a3c8353d3e04acf75b3fed57ba41f5c0646bbf1d10c7c282291c97936b4",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/5d/22/9b8d458c2881b22df3db5bb3e7369e63d527d986decb6c11a591ba2364f7/coverage-7.10.7-cp313-cp313t-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:1ef2319dd15a0b009667301a3f84452a4dc6fddfd06b0c5c53ea472d3989fbf0",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/f7/08/16bee2c433e60913c610ea200b276e8eeef084b0d200bdcff69920bd5828/coverage-7.10.7-cp313-cp313t-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:83082a57783239717ceb0ad584de3c69cf581b2a95ed6bf81ea66034f00401c0",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/20/9d/e53eb9771d154859b084b90201e5221bca7674ba449a17c101a5031d4054/coverage-7.10.7-cp313-cp313t-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:50aa94fb1fb9a397eaa19c0d5ec15a5edd03a47bf1a3a6111a16b36e190cff65",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ad/b0/69bc7050f8d4e56a89fb550a1577d5d0d1db2278106f6f626464067b3817/coverage-7.10.7-cp313-cp313t-musllinux_1_2_aarch64.whl",
        hash = "sha256:2120043f147bebb41c85b97ac45dd173595ff14f2a584f2963891cbcc3091541",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ef/4b/2514b060dbd1bc0aaf23b852c14bb5818f244c664cb16517feff6bb3a5ab/coverage-7.10.7-cp313-cp313t-musllinux_1_2_i686.whl",
        hash = "sha256:2fafd773231dd0378fdba66d339f84904a8e57a262f583530f4f156ab83863e6",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/54/78/7ba2175007c246d75e496f64c06e94122bdb914790a1285d627a918bd271/coverage-7.10.7-cp313-cp313t-musllinux_1_2_riscv64.whl",
        hash = "sha256:0b944ee8459f515f28b851728ad224fa2d068f1513ef6b7ff1efafeb2185f999",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/c0/b3/fac9f7abbc841409b9a410309d73bfa6cfb2e51c3fada738cb607ce174f8/coverage-7.10.7-cp313-cp313t-musllinux_1_2_x86_64.whl",
        hash = "sha256:4b583b97ab2e3efe1b3e75248a9b333bd3f8b0b1b8e5b45578e05e5850dfb2c2",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ee/51/a03bec00d37faaa891b3ff7387192cef20f01604e5283a5fabc95346befa/coverage-7.10.7-cp313-cp313t-win32.whl",
        hash = "sha256:2a78cd46550081a7909b3329e2266204d584866e8d97b898cd7fb5ac8d888b1a",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/53/22/3cf25d614e64bf6d8e59c7c669b20d6d940bb337bdee5900b9ca41c820bb/coverage-7.10.7-cp313-cp313t-win_amd64.whl",
        hash = "sha256:33a5e6396ab684cb43dc7befa386258acb2d7fae7f67330ebb85ba4ea27938eb",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/49/a1/00164f6d30d8a01c3c9c48418a7a5be394de5349b421b9ee019f380df2a0/coverage-7.10.7-cp313-cp313t-win_arm64.whl",
        hash = "sha256:86b0e7308289ddde73d863b7683f596d8d21c7d8664ce1dee061d0bcf3fbb4bb",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/23/9c/5844ab4ca6a4dd97a1850e030a15ec7d292b5c5cb93082979225126e35dd/coverage-7.10.7-cp314-cp314-macosx_10_13_x86_64.whl",
        hash = "sha256:b06f260b16ead11643a5a9f955bd4b5fd76c1a4c6796aeade8520095b75de520",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/f0/89/673f6514b0961d1f0e20ddc242e9342f6da21eaba3489901b565c0689f34/coverage-7.10.7-cp314-cp314-macosx_11_0_arm64.whl",
        hash = "sha256:212f8f2e0612778f09c55dd4872cb1f64a1f2b074393d139278ce902064d5b32",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/05/e8/261cae479e85232828fb17ad536765c88dd818c8470aca690b0ac6feeaa3/coverage-7.10.7-cp314-cp314-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:3445258bcded7d4aa630ab8296dea4d3f15a255588dd535f980c193ab6b95f3f",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/82/62/14ed6546d0207e6eda876434e3e8475a3e9adbe32110ce896c9e0c06bb9a/coverage-7.10.7-cp314-cp314-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:bb45474711ba385c46a0bfe696c695a929ae69ac636cda8f532be9e8c93d720a",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ff/49/07f00db9ac6478e4358165a08fb41b469a1b053212e8a00cb02f0d27a05f/coverage-7.10.7-cp314-cp314-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:813922f35bd800dca9994c5971883cbc0d291128a5de6b167c7aa697fcf59360",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a2/59/c5201c62dbf165dfbc91460f6dbbaa85a8b82cfa6131ac45d6c1bfb52deb/coverage-7.10.7-cp314-cp314-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:93c1b03552081b2a4423091d6fb3787265b8f86af404cff98d1b5342713bdd69",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/07/ae/5920097195291a51fb00b3a70b9bbd2edbfe3c84876a1762bd1ef1565ebc/coverage-7.10.7-cp314-cp314-musllinux_1_2_aarch64.whl",
        hash = "sha256:cc87dd1b6eaf0b848eebb1c86469b9f72a1891cb42ac7adcfbce75eadb13dd14",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/b9/3c/a815dde77a2981f5743a60b63df31cb322c944843e57dbd579326625a413/coverage-7.10.7-cp314-cp314-musllinux_1_2_i686.whl",
        hash = "sha256:39508ffda4f343c35f3236fe8d1a6634a51f4581226a1262769d7f970e73bffe",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/aa/99/f5cdd8421ea656abefb6c0ce92556709db2265c41e8f9fc6c8ae0f7824c9/coverage-7.10.7-cp314-cp314-musllinux_1_2_riscv64.whl",
        hash = "sha256:925a1edf3d810537c5a3abe78ec5530160c5f9a26b1f4270b40e62cc79304a1e",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/c3/7a/e9a2da6a1fc5d007dd51fca083a663ab930a8c4d149c087732a5dbaa0029/coverage-7.10.7-cp314-cp314-musllinux_1_2_x86_64.whl",
        hash = "sha256:2c8b9a0636f94c43cd3576811e05b89aa9bc2d0a85137affc544ae5cb0e4bfbd",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ef/5b/0b5799aa30380a949005a353715095d6d1da81927d6dbed5def2200a4e25/coverage-7.10.7-cp314-cp314-win32.whl",
        hash = "sha256:b7b8288eb7cdd268b0304632da8cb0bb93fadcfec2fe5712f7b9cc8f4d487be2",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/da/b0/e802fbb6eb746de006490abc9bb554b708918b6774b722bb3a0e6aa1b7de/coverage-7.10.7-cp314-cp314-win_amd64.whl",
        hash = "sha256:1ca6db7c8807fb9e755d0379ccc39017ce0a84dcd26d14b5a03b78563776f681",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/9e/e8/71d0c8e374e31f39e3389bb0bd19e527d46f00ea8571ec7ec8fd261d8b44/coverage-7.10.7-cp314-cp314-win_arm64.whl",
        hash = "sha256:097c1591f5af4496226d5783d036bf6fd6cd0cbc132e071b33861de756efb880",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/62/09/9a5608d319fa3eba7a2019addeacb8c746fb50872b57a724c9f79f146969/coverage-7.10.7-cp314-cp314t-macosx_10_13_x86_64.whl",
        hash = "sha256:a62c6ef0d50e6de320c270ff91d9dd0a05e7250cac2a800b7784bae474506e63",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/f5/6f/f58d46f33db9f2e3647b2d0764704548c184e6f5e014bef528b7f979ef84/coverage-7.10.7-cp314-cp314t-macosx_11_0_arm64.whl",
        hash = "sha256:9fa6e4dd51fe15d8738708a973470f67a855ca50002294852e9571cdbd9433f2",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/74/5c/183ffc817ba68e0b443b8c934c8795553eb0c14573813415bd59941ee165/coverage-7.10.7-cp314-cp314t-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:8fb190658865565c549b6b4706856d6a7b09302c797eb2cf8e7fe9dabb043f0d",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/0f/48/71a8abe9c1ad7e97548835e3cc1adbf361e743e9d60310c5f75c9e7bf847/coverage-7.10.7-cp314-cp314t-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:affef7c76a9ef259187ef31599a9260330e0335a3011732c4b9effa01e1cd6e0",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/84/fd/193a8fb132acfc0a901f72020e54be5e48021e1575bb327d8ee1097a28fd/coverage-7.10.7-cp314-cp314t-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:6e16e07d85ca0cf8bafe5f5d23a0b850064e8e945d5677492b06bbe6f09cc699",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/b1/8f/74ecc30607dd95ad50e3034221113ccb1c6d4e8085cc761134782995daae/coverage-7.10.7-cp314-cp314t-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:03ffc58aacdf65d2a82bbeb1ffe4d01ead4017a21bfd0454983b88ca73af94b9",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/0f/55/79ff53a769f20d71b07023ea115c9167c0bb56f281320520cf64c5298a96/coverage-7.10.7-cp314-cp314t-musllinux_1_2_aarch64.whl",
        hash = "sha256:1b4fd784344d4e52647fd7857b2af5b3fbe6c239b0b5fa63e94eb67320770e0f",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/88/e2/dac66c140009b61ac3fc13af673a574b00c16efdf04f9b5c740703e953c0/coverage-7.10.7-cp314-cp314t-musllinux_1_2_i686.whl",
        hash = "sha256:0ebbaddb2c19b71912c6f2518e791aa8b9f054985a0769bdb3a53ebbc765c6a1",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a2/f1/f48f645e3f33bb9ca8a496bc4a9671b52f2f353146233ebd7c1df6160440/coverage-7.10.7-cp314-cp314t-musllinux_1_2_riscv64.whl",
        hash = "sha256:a2d9a3b260cc1d1dbdb1c582e63ddcf5363426a1a68faa0f5da28d8ee3c722a0",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/bb/3b/8442618972c51a7affeead957995cfa8323c0c9bcf8fa5a027421f720ff4/coverage-7.10.7-cp314-cp314t-musllinux_1_2_x86_64.whl",
        hash = "sha256:a3cc8638b2480865eaa3926d192e64ce6c51e3d29c849e09d5b4ad95efae5399",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/b2/dc/101f3fa3a45146db0cb03f5b4376e24c0aac818309da23e2de0c75295a91/coverage-7.10.7-cp314-cp314t-win32.whl",
        hash = "sha256:67f8c5cbcd3deb7a60b3345dffc89a961a484ed0af1f6f73de91705cc6e31235",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/4c/a1/74c51803fc70a8a40d7346660379e144be772bab4ac7bb6e6b905152345c/coverage-7.10.7-cp314-cp314t-win_amd64.whl",
        hash = "sha256:e1ed71194ef6dea7ed2d5cb5f7243d4bcd334bfb63e59878519be558078f848d",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/12/65/f116a6d2127df30bcafbceef0302d8a64ba87488bf6f73a6d8eebf060873/coverage-7.10.7-cp314-cp314t-win_arm64.whl",
        hash = "sha256:7fe650342addd8524ca63d77b2362b02345e5f1a093266787d210c70a50b471a",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a3/ad/d1c25053764b4c42eb294aae92ab617d2e4f803397f9c7c8295caa77a260/coverage-7.10.7-cp39-cp39-macosx_10_9_x86_64.whl",
        hash = "sha256:fff7b9c3f19957020cac546c70025331113d2e61537f6e2441bc7657913de7d3",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/52/2f/b9f9daa39b80ece0b9548bbb723381e29bc664822d9a12c2135f8922c22b/coverage-7.10.7-cp39-cp39-macosx_11_0_arm64.whl",
        hash = "sha256:bc91b314cef27742da486d6839b677b3f2793dfe52b51bbbb7cf736d5c29281c",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/dd/6e/30d006c3b469e58449650642383dddf1c8fb63d44fdf92994bfd46570695/coverage-7.10.7-cp39-cp39-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:567f5c155eda8df1d3d439d40a45a6a5f029b429b06648235f1e7e51b522b396",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/b0/49/8a070782ce7e6b94ff6a0b6d7c65ba6bc3091d92a92cef4cd4eb0767965c/coverage-7.10.7-cp39-cp39-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:2af88deffcc8a4d5974cf2d502251bc3b2db8461f0b66d80a449c33757aa9f40",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/6a/92/1c1c5a9e8677ce56d42b97bdaca337b2d4d9ebe703d8c174ede52dbabd5f/coverage-7.10.7-cp39-cp39-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:c7315339eae3b24c2d2fa1ed7d7a38654cba34a13ef19fbcb9425da46d3dc594",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/c0/54/b140edee7257e815de7426d5d9846b58505dffc29795fff2dfb7f8a1c5a0/coverage-7.10.7-cp39-cp39-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:912e6ebc7a6e4adfdbb1aec371ad04c68854cd3bf3608b3514e7ff9062931d8a",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/e4/9e/6d6b8295940b118e8b7083b29226c71f6154f7ff41e9ca431f03de2eac0d/coverage-7.10.7-cp39-cp39-musllinux_1_2_aarch64.whl",
        hash = "sha256:f49a05acd3dfe1ce9715b657e28d138578bc40126760efb962322c56e9ca344b",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/db/e5/5e957ca747d43dbe4d9714358375c7546cb3cb533007b6813fc20fce37ad/coverage-7.10.7-cp39-cp39-musllinux_1_2_i686.whl",
        hash = "sha256:cce2109b6219f22ece99db7644b9622f54a4e915dad65660ec435e89a3ea7cc3",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/9a/45/540fc5cc92536a1b783b7ef99450bd55a4b3af234aae35a18a339973ce30/coverage-7.10.7-cp39-cp39-musllinux_1_2_riscv64.whl",
        hash = "sha256:f3c887f96407cea3916294046fc7dab611c2552beadbed4ea901cbc6a40cc7a0",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/75/0b/8287b2e5b38c8fe15d7e3398849bb58d382aedc0864ea0fa1820e8630491/coverage-7.10.7-cp39-cp39-musllinux_1_2_x86_64.whl",
        hash = "sha256:635adb9a4507c9fd2ed65f39693fa31c9a3ee3a8e6dc64df033e8fdf52a7003f",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/0c/1d/29724999984740f0c86d03e6420b942439bf5bd7f54d4382cae386a9d1e9/coverage-7.10.7-cp39-cp39-win32.whl",
        hash = "sha256:5a02d5a850e2979b0a014c412573953995174743a3f7fa4ea5a6e9a3c5617431",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/43/11/4b1e6b129943f905ca54c339f343877b55b365ae2558806c1be4f7476ed5/coverage-7.10.7-cp39-cp39-win_amd64.whl",
        hash = "sha256:c134869d5ffe34547d14e174c866fd8fe2254918cc0a95e99052903bc1543e07",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ec/16/114df1c291c22cac3b0c127a73e0af5c12ed7bbb6558d310429a0ae24023/coverage-7.10.7-py3-none-any.whl",
        hash = "sha256:f7941f6f2fe6dd6807a1208737b8a0cbcf1cc6d7b07d24998ad2d63590868260",
        marker = "python_full_version < '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/5e/9d/e3db9071ebeda48e47e5be0fd0404219954e7888f64e7c37df324a79dc3a/coverage-7.17.2-cp311-cp311-macosx_10_9_x86_64.whl",
        hash = "sha256:a3f49ac9c9e5fd4b450677eb44f4b14ea9ab71950b2896888c9f6a22d5cd1773",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/49/a1/260786d936940102052a51cb166f80f4a98e67fb6142aa050f1af48a2385/coverage-7.17.2-cp311-cp311-macosx_11_0_arm64.whl",
        hash = "sha256:3d3d9d79a2b6cdcdde5a1ab1ae89953faea5cb28c0eea17a413ad997bb3cc8a1",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/be/80/f5176b7f6aa9e05e37e1bb5eae473c5d015485c36206934f53b2b2795076/coverage-7.17.2-cp311-cp311-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:5b71aeaa4440cbece5498acda30838685793d3bb960aff87ec97fbb546715a5f",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/03/9f/4669ca11ce1932cc18fce766ead327ceb41a92055608c179b137067e2805/coverage-7.17.2-cp311-cp311-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:01303d9e68b6e6bdc5459b54e3bd0e3539c94c25b50ac7362b7cbcacbc815fbc",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ae/99/efefaa02a4b2876ffa4a389c81a8074c888442b12c64046b448718fa5590/coverage-7.17.2-cp311-cp311-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:1947bd9d82e405c892c50b0d8dc0c1dea5df2a962129ca238c500a6bcf887509",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/19/2f/a565096e5dcf8c511332d397d712b056f06091ab3efc10adb5a4d22b0cc2/coverage-7.17.2-cp311-cp311-manylinux2014_ppc64le.manylinux_2_17_ppc64le.manylinux_2_28_ppc64le.whl",
        hash = "sha256:2cd1a7472a972fed01c89589b1560846e32e942f8329a515c4059d4521c6579a",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ab/09/87f9b02f97179f2c76fa5724e0ce00b9db2bbe16b7e21d89c8fc1f3a77d9/coverage-7.17.2-cp311-cp311-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:2b7fe217808239437b8509b869fde2e0cac48776a68c626bd6b15411b087e3de",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/db/12/70733b58d508bc80dc983408b06f1fd0c59fde0eb1379dd9473b3e290856/coverage-7.17.2-cp311-cp311-musllinux_1_2_aarch64.whl",
        hash = "sha256:565f1f1a9632d82678525d668a10fe070a285603a9d3581505b0e1a66624ad50",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/33/de/0495b108a3091f2389800455b615939867a3ac19f24f0fc186f4d066b4f3/coverage-7.17.2-cp311-cp311-musllinux_1_2_i686.whl",
        hash = "sha256:189cdffb3ebc53d6133de67952dac7cc88d1fcaff5480623fb00ef0bf1cef918",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/0f/ff/39cda949e0e9bbc16620d8b843fd78929a46edda2566e54b9597bda61625/coverage-7.17.2-cp311-cp311-musllinux_1_2_ppc64le.whl",
        hash = "sha256:f25209696631752468a25e5954fe119503468b3b29b6fa2c621ae766153c6f50",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/85/e5/0eb1bbfc80e1a03318d81fc044dc1c4fc075921f7f618298d42837dafa66/coverage-7.17.2-cp311-cp311-musllinux_1_2_riscv64.whl",
        hash = "sha256:20faaaf3a49601afbcd6d46c17a594b0ae62631498def44e5eed94789962ea18",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a7/18/098ea8ee450922eec7ab48a35b4a7fd6a49c4a97416d1e4cf66092c24dc4/coverage-7.17.2-cp311-cp311-musllinux_1_2_x86_64.whl",
        hash = "sha256:7c123b6bbc183a14372036769f033098026aa75fc8fba37d028b0b772356e90b",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/8e/1c/a6ee041c4bc8b6ec7bc9f417daf89e3ee702182a48d573267ccaaed17c64/coverage-7.17.2-cp311-cp311-win32.whl",
        hash = "sha256:1c3146ef9d14c011517422489784a7ac344477e9cdacb05d9529e912721cd5d8",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/5a/df/7f077fb2e71b1d73fe8285be7c6ba43dc085f9eaa2384d4e8e55560073a3/coverage-7.17.2-cp311-cp311-win_amd64.whl",
        hash = "sha256:51c6a60e63ea993113ea5cd24a401cc2faddc54aa7acfddaffa5d3b8c0161b9d",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/90/56/89dcd5907d0cc04b07746e62e1cb896c0f694e5af40aa0c980458825c6c5/coverage-7.17.2-cp311-cp311-win_arm64.whl",
        hash = "sha256:b08ee3ef53e80e5a50c68b3d9764363e373acba540e1b58daee0a9a7f23fdfb2",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/22/6a/a51808ac625c457326fb37b174d35e1badb1324c6def5d9668089c4b14ef/coverage-7.17.2-cp312-cp312-macosx_10_13_x86_64.whl",
        hash = "sha256:289a24443352713745f79c1b6aae4e99ced2f5ff3e86bb630c33c631d50f217c",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/31/24/f32ec1a5ef947294252e77c5d40ac0903ba1de4c92638edfcca8629c067f/coverage-7.17.2-cp312-cp312-macosx_11_0_arm64.whl",
        hash = "sha256:da4b0aef427eb96e422b444e5c2c3d38768fedb9141346294c38717a8b15b416",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/01/8e/3097367327c69e65521b9d9bf8b9d2ddecefa8c21bd08e17bc068bd3db93/coverage-7.17.2-cp312-cp312-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:90c6c5f93606b8803bd7f8a0b2ae05df7e35da4504a1c53cfe9294a1731e1f49",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/73/65/774fc4ec86807b6ee66b46465bc49b34bb6d291e9bff6ddfa9708ccb4053/coverage-7.17.2-cp312-cp312-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:36314997533266bde3d07765289674304d61bfe49165bb1b4fa9be12cb4ba0d1",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/d8/72/17b5df5d8211e1880169b93197ba98b21b30ccf8f116284536113b7582c5/coverage-7.17.2-cp312-cp312-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:1682d98ded28524bc6853cc4e7c65175b3e917f38b2e2ddebb28cafd8ab4de74",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/de/0c/603ba7fff1aa4c8064fdf4a1fff6d9fb51c72a5828429dfe858be48e38b3/coverage-7.17.2-cp312-cp312-manylinux2014_ppc64le.manylinux_2_17_ppc64le.manylinux_2_28_ppc64le.whl",
        hash = "sha256:8eab0a5cff8dbc563d1416a6e079ba3c146712e47167c022a5df5ea01bd76df9",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/f4/ca/f2ae6e47e18b35a0dbddb9d8f51be34a6d66b41120f2e0f7363ccc0812f4/coverage-7.17.2-cp312-cp312-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:635337a96895f2ffcfe2aa7554468a988f468fb67a8007c1a65e95148c1855a9",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/b2/4b/b09540a46395a6a1052ad114bf366e383c64e223374f4911a85620667930/coverage-7.17.2-cp312-cp312-musllinux_1_2_aarch64.whl",
        hash = "sha256:79cd2d9742419b6d1aaeb1f3fb77a8e6a01c09ebe5bd1b27011752410a5e3781",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ec/c4/42783cb43481fafafffbc7be7fe6026258ffd30a575707733109c9ef0679/coverage-7.17.2-cp312-cp312-musllinux_1_2_i686.whl",
        hash = "sha256:b0209fff1ca92f1e2e344d54b5b3def74efbdb46ba807cd81976a5e9e569cac3",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/37/07/192ee81dd1ec4da58ae0f03fdd0045d2b821007e4194f7704d6e495733f0/coverage-7.17.2-cp312-cp312-musllinux_1_2_ppc64le.whl",
        hash = "sha256:7a3984fb8c2407721f9bc05573fc9a770752efc756d55068ccbde1fe53e42233",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/dd/94/8d983310d98299a19ba23efbb324492f4bf8d8668d610eacd304e451f138/coverage-7.17.2-cp312-cp312-musllinux_1_2_riscv64.whl",
        hash = "sha256:698ca1575135215be25ac9c5d14f0b5455135d29602b7ee81e511d64a0435c85",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/1a/85/6c923d71c76566c6c65a2af104d39d69d44ae708a700de017e6c56fedfc6/coverage-7.17.2-cp312-cp312-musllinux_1_2_x86_64.whl",
        hash = "sha256:686b6f8f9e57afc3a44096b17ee8de7e11e0a12f2da819e25047af1eb3b0fc6f",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/54/f9/fd3c37b09891bfdfece486a6145345bf2b32332045a678afd293a7f2f05d/coverage-7.17.2-cp312-cp312-win32.whl",
        hash = "sha256:ee083412170118074bcc74361fcbc7104eb6d0b7c9c75eb3b84a4c324410c531",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/dc/b8/4d395163c9bfae0e991abbd14dea9c9bbb4ade904e5f297cbfb7b8150216/coverage-7.17.2-cp312-cp312-win_amd64.whl",
        hash = "sha256:e269dddf5ebac20dfcc5a2a459528a9d221ab828cb31dfdf19c7cfacdbcee673",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a3/02/1024b8d4f60a9ecc0ee41a6000425caa63855d63e51da84c93c0b1dff894/coverage-7.17.2-cp312-cp312-win_arm64.whl",
        hash = "sha256:bac3c79c31f45274117ed64c65efeaed85665668aeba7d809c7c38801ada6ed4",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/e0/32/d750d7b10b0a9436349b3fb78491c5bb8f9b524f01ae6994d935d77d6ab8/coverage-7.17.2-cp313-cp313-android_24_arm64_v8a.whl",
        hash = "sha256:882cade9b6dc43b2bc819bb444c0a13e4ed1f669a50e0de74adeec54fce486f3",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/63/33/468f8c63aff5deef81bfb8e44771f68ebba328c0aa46c8a6ff27dedd0fda/coverage-7.17.2-cp313-cp313-android_24_x86_64.whl",
        hash = "sha256:f5a875e92f10c6463027d8151459f2d92b4c13527402ed1301eaddabd79d8cf5",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/10/91/c8723e48c1497a3c56a3194973a416a6f0fb24560425685f960888e03b20/coverage-7.17.2-cp313-cp313-ios_13_0_arm64_iphoneos.whl",
        hash = "sha256:e8da5e158d13556457f69245deacf6d8401a2c9c31afaddd18bea691e849b5fd",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/61/4f/2f57b3dc6ef31e12a99e6dcb820c4ab04d973ea1466f73c856bf920a740c/coverage-7.17.2-cp313-cp313-ios_13_0_arm64_iphonesimulator.whl",
        hash = "sha256:42133a2647982db7968db138c0f4a57f5836101d8d504600a87ef8ebfa22a4cf",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/9c/fa/967e829238dda21c4bce17aef2f739187678c8e6e6fc880a8454945a7433/coverage-7.17.2-cp313-cp313-macosx_10_13_x86_64.whl",
        hash = "sha256:e6c89d63d43738712ce1febddb7758ffeb56de08f1b2be68aeb9a9c7fee712c7",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/9d/df/803ba08e8937759dc3f18b93ece82f81b2fb446e3846e4d60a06a4e77647/coverage-7.17.2-cp313-cp313-macosx_11_0_arm64.whl",
        hash = "sha256:f94d465ee00ebe694ca866d66bbe45fa04618b1afcb377de934694f624fa7cf6",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/4a/12/92dcd9206e7bb817af42b8663cfeefdbb2c5a6c92cc7069d43e6892bbdeb/coverage-7.17.2-cp313-cp313-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:7ce0acb27a823e8e5169282f538f0e182854cc8b472b88d45456f09b6fe364fd",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/48/2d/6b028df8050caef4ce0df177686c92dba16ab7cf004040e5518f95b57021/coverage-7.17.2-cp313-cp313-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:70daa8e4b49541b51c0baeba0d802b0d14d3214daeebc071b3db0b0c7dc84646",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/62/c3/429b500937ac446e36fcce517d040b0b8bd04a4bfa087bdf864175553fea/coverage-7.17.2-cp313-cp313-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:95bd8dc5b356f78f10a967ec50f8902d56f24c623753ac9fce0aba9d6213d5c5",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/c1/91/263224a77de3ab1ee42d110b09f1ac9a02638794d3e002a859822638256a/coverage-7.17.2-cp313-cp313-manylinux2014_ppc64le.manylinux_2_17_ppc64le.manylinux_2_28_ppc64le.whl",
        hash = "sha256:a5565a9dd715a5a94ffcf9a0ad4b6b1501b5441fd67d660e78742adff5d37a0a",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/0f/44/99b72f2961f4ba54ac14ccb016f3b212cc9a9dfda4c37e07a208efe01f9f/coverage-7.17.2-cp313-cp313-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:091eba4248d31b03828fc657c96d14adfaa8754f5aec7b73298b82894858db06",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/be/a7/e97f63a7c345077e4e398d15e3aa5068edc28cb061f997f71fd0e32703e1/coverage-7.17.2-cp313-cp313-musllinux_1_2_aarch64.whl",
        hash = "sha256:d2742952851c7f88b1484385f68c42c6388153520efb40ff09fc852c3783aa5c",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/16/0c/73e470df7db83962e2cdd6c1a7ca7dc8f8632c17a6d378d6d9124ff8bc6b/coverage-7.17.2-cp313-cp313-musllinux_1_2_i686.whl",
        hash = "sha256:1da1999e3c371edd669b48a1029c86dc0474cdc6ff152d58cb3f15cb3337af72",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/50/43/db8bc1b92d933b0b5f57d0e3377594c4f78ea31e84e8fbc22627fd17ecf4/coverage-7.17.2-cp313-cp313-musllinux_1_2_ppc64le.whl",
        hash = "sha256:7804a6022fcd5e1d4de4dc676e985d6aea0119249e88c041e943f3cd07953527",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/c4/f4/3e9e5cc9ccc911f8fb9595053da1ce58b9de8941b27e2f2f7058cdfc87f1/coverage-7.17.2-cp313-cp313-musllinux_1_2_riscv64.whl",
        hash = "sha256:6bdf3821fd0740b5369b9ab58b4e9d0d68a2c5c75a7ee0cd3beb624f9f15e4fa",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/72/9f/0d67883bf55adf50424728937cbee54d76fa137817e6bb20f97061d01816/coverage-7.17.2-cp313-cp313-musllinux_1_2_x86_64.whl",
        hash = "sha256:e09c37817768bb71fe3e70b6ce5e6ac1a0cd7398536c2f30a4460218c7b66e93",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a8/22/71965edc14736073b55a40e521791d9233d5c3194fa6887a94f4431fbbcc/coverage-7.17.2-cp313-cp313-win32.whl",
        hash = "sha256:c10f2a2748dd084e44811bb9b26979763af9003115d9bf93c1da69011944719f",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/47/0d/715cb37f51f908a6f6f33fe8c6fc95ab638b17cb014b1650daae0893c160/coverage-7.17.2-cp313-cp313-win_amd64.whl",
        hash = "sha256:8dc07ed34bcb206f69d5b54fd3874f7bf39ac941c9f7aec2b53b29874fcfd77a",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/39/f2/a5099bdc2a530f29c818a1c7e706669451c10e5f0eb62dcff76ef3568668/coverage-7.17.2-cp313-cp313-win_arm64.whl",
        hash = "sha256:bb74283661a239fdaf738ac0b07db4ed9b476c7532d3e713abf0f6a072781e60",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/96/f9/30d6ff7a66e1519d79940fdee542ead9a63601de60be5cc9fe62c74bab58/coverage-7.17.2-cp314-cp314-android_24_arm64_v8a.whl",
        hash = "sha256:0439f77deb5c023003533ae8909a9aa1e174c847d655327035b1e542c7c8a54e",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/1a/db/82c722c37dce98fe1abc953768903752bdd415dfe8cfeb7b744a7236a735/coverage-7.17.2-cp314-cp314-android_24_x86_64.whl",
        hash = "sha256:e86a66f96d80c770daeed78394c1d4f6e8d03e5a3e08c5dab5275d56414f296a",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/7d/07/71b68d870975776cb185f11cd80e053b01739f3646488fe8b9721744f56a/coverage-7.17.2-cp314-cp314-ios_13_0_arm64_iphoneos.whl",
        hash = "sha256:87b30f3daa0bedda6b770b303410a6def007844772aaa143dc52675b3d95cd8a",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/aa/23/ed60f79576175e108c77df2bdc116f46e367aab108542ddeecaab752f0f6/coverage-7.17.2-cp314-cp314-ios_13_0_arm64_iphonesimulator.whl",
        hash = "sha256:3f219efbc3ec71c377e278dee201633e1d4ad0d2d9bdaddfd9489b2869d584c4",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/10/7e/60a51850d3ff659b82cc211bc98fa126aab2ac9b81bd4ed6abc3e3720a09/coverage-7.17.2-cp314-cp314-macosx_10_15_x86_64.whl",
        hash = "sha256:36248fb6c03341501169539bcab35eb3a59159100be1246fad3c14cb73c17685",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/77/80/a9539c15076fb9b95d8cbdb7f0caec90857d80bddca3eeca439f5e2e64e2/coverage-7.17.2-cp314-cp314-macosx_11_0_arm64.whl",
        hash = "sha256:2a6281011cf85699763bf88ab55e0774f6696f87b390f39152b14ecefadccb59",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/7f/3b/0a84b6032511834105fd4f8a8b4e76927783cea03dc4796032d5c4bfec8b/coverage-7.17.2-cp314-cp314-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:3dfefb1ec16ca1a01e5da40ba162e268ced8bd3624b9eba4e9384ebfa14af7ec",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/2e/e4/a3e6b8bcc219b00ea91e36f071c2659b253e5d6e1b258c31eb4524231718/coverage-7.17.2-cp314-cp314-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:34e5c7a2da36804c6e6f10b368eae01ad56f5a4ac5ecce7297300a3d46fdef2a",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/05/54/a666b65c5bb145d8796b7902ff1c0f60600a6c2a08949e20f2fb7af15de3/coverage-7.17.2-cp314-cp314-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:e6bf531deaebf8f69ba6015bba3fb817cab6694dfb69ac2a708889dc59a3926e",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a6/73/ac9d06da9e0c143b874a68b17d8dfeedc45acdf1bdcee5b22a42bece098e/coverage-7.17.2-cp314-cp314-manylinux2014_ppc64le.manylinux_2_17_ppc64le.manylinux_2_28_ppc64le.whl",
        hash = "sha256:88d4dc83b6ad09a2134cad9d8ec780b274b17ac7dfba8c2c6e92e3bc468fe85d",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/87/b1/8a500e16cf787383b00b5a86eb50a490b4d8ebde505f92e1aaca515afc0a/coverage-7.17.2-cp314-cp314-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:8dc17707fd463b4dfab53792e41d50a23316ac6b98539007aa2388a1d44a8535",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/f7/be/642762c5973b89e2b8bf66c95778bdd80e96ceea442ae8fa753732597b73/coverage-7.17.2-cp314-cp314-musllinux_1_2_aarch64.whl",
        hash = "sha256:df0a34d445eea64f3766e9ca2ff57bcde600a89c7c0330434a7a37e8d6e2549f",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/e4/b1/f7d6c0ef0a4aecf3f91f19df4ab3fa131fec8c89f554187511716584c9f5/coverage-7.17.2-cp314-cp314-musllinux_1_2_i686.whl",
        hash = "sha256:c5a98aff9eb681312ed403ecb7beb5f15fd25d6e0acc2554b9ca4b4d6f0b6705",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/c7/c0/3ae087d52cfa5119ad9ecbd193c40089924d1101cef7333f15a86dccb444/coverage-7.17.2-cp314-cp314-musllinux_1_2_ppc64le.whl",
        hash = "sha256:7565c17092f2f4021abbe3f5007300c224f362364a388f5ddad9216dab44b611",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/c5/95/d324108991f892cb361ef8b2f91bd4cda9c2563e0954247409e9e6b911ab/coverage-7.17.2-cp314-cp314-musllinux_1_2_riscv64.whl",
        hash = "sha256:555257578e20a46020c27b2af4ef99059cd906aa9b8e163baf9da9a5afb65a64",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/14/b5/13a62eac66cecbaaa098bb753a3693b44454a4d21d53db4f1a0953f35f0b/coverage-7.17.2-cp314-cp314-musllinux_1_2_x86_64.whl",
        hash = "sha256:460ba2139866e758c3a8e9d9422fdc889942bcbc5ccaf710dc4fbd8707d14aa8",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/53/13/9ea31cfa72434449b9a98666760169d1e0ab31b3f6cdb12e68149106668e/coverage-7.17.2-cp314-cp314-win32.whl",
        hash = "sha256:e72cf9556f799c3fce7597c1bd7dbfc9104befbd08088deb3b9ae9fd98117c02",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/f6/cc/aa8f34b014979c973740f5a5ed6861ecfc6009082c70e72030ca1519e0f8/coverage-7.17.2-cp314-cp314-win_amd64.whl",
        hash = "sha256:205f9e329d9d5e47c320f8712326a01620689edae50531cc8934511e2c5e8f7e",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/49/64/16afaa19b3886dc157c3c5ebace5241b84b96a005cb28545584e66b80895/coverage-7.17.2-cp314-cp314-win_arm64.whl",
        hash = "sha256:a5909dd087006c70c128297312ba67d877123e871100645d9bd73ae021a4d01d",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/e8/95/acc865e1411c8ebc5c5d230367f3bfed5c605ed54bb41b84fc58f4e7f137/coverage-7.17.2-cp314-cp314t-macosx_10_15_x86_64.whl",
        hash = "sha256:674bcd023a3743666d4d7a15238e57a00c968553780a36c80d3779fc410b912c",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/10/98/02c37c6a928ccfc84b7a43eda44d96d3b1ccbc93989c178754b7e67e7650/coverage-7.17.2-cp314-cp314t-macosx_11_0_arm64.whl",
        hash = "sha256:ba45dc072bfbf1798e68ec81379b73473fc912174bff9f91924d77711a1d2b30",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/28/ab/d503b0aaebb92b171260469463915af5e16a64457b289d4cb844e8c366ac/coverage-7.17.2-cp314-cp314t-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:0d8a5dc709da9b90ad5cc859a9b88c9b801e65ca2fbf7cbdbed5b9cbf457fcc9",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/f6/e5/6d6ba15bde22fcccd07e14305be14291d041f732771a73f787297445d3e7/coverage-7.17.2-cp314-cp314t-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:248873a144c067f981742ff4bbfb48b57e281a8cb7a3821d4e293bdb50b47970",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/63/e7/bd6dcec5b8130f5bd8679087a2bc3a50a53c4ee78d5ec449610020088ff3/coverage-7.17.2-cp314-cp314t-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:d0332e2b27fc5cc761d6b8a33118b958e6a46be7f00fd30e03a5cf103350c0b3",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/55/c1/b3f06aa1f1c51f4295fdfa6500eb7409aaa6273cf5f27bafc25217f3547d/coverage-7.17.2-cp314-cp314t-manylinux2014_ppc64le.manylinux_2_17_ppc64le.manylinux_2_28_ppc64le.whl",
        hash = "sha256:27fc4384a1154f7df30d304ccddc05ef457368c065670ecbd392606279b3329a",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a7/f0/b68ab3654af3541488b26856e3043c13c782d8e6104fc8149746ecaa83f0/coverage-7.17.2-cp314-cp314t-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:603140eeae3f9adc562f91b1b98d4d1fc491bd1f66c5082482c568d0b7891bb1",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/fd/16/4a9d56bd4ca4572cbd20f9843813623cef1b88b15f979ec4f381704d2f84/coverage-7.17.2-cp314-cp314t-musllinux_1_2_aarch64.whl",
        hash = "sha256:be0fec33b69c40f845c76f67fb4495b62a84da8c31a579dc6e18c5a63fa6a1f3",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/78/d2/1c04b38bab92d2b7d62718d170b5bea43755fefee7e29cc056448c433d92/coverage-7.17.2-cp314-cp314t-musllinux_1_2_i686.whl",
        hash = "sha256:960e199965e506d78f62252355397a05c8cee8072ad2d82d932745517d566539",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/26/c9/2c639e9aee78b0522cb3dc245de09685e34b479bcc45d4d2a277d0de1174/coverage-7.17.2-cp314-cp314t-musllinux_1_2_ppc64le.whl",
        hash = "sha256:d7a363c0788435ff5324d9582d37c63f215c75f974d755cfd6cfc9fbe0e64b04",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/79/1f/11bdaf03c1b12f88094b57420b4238d3974ebec6a7d674b645a54e24f90c/coverage-7.17.2-cp314-cp314t-musllinux_1_2_riscv64.whl",
        hash = "sha256:afd81658f17b1a50bbc1d247a61fa435be0be471246136eb946f9cbfc437a4fa",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/bb/f6/43d40d1b4d4892e54c68a241cd5b92efed4d5934109e0e5e24a94759f732/coverage-7.17.2-cp314-cp314t-musllinux_1_2_x86_64.whl",
        hash = "sha256:d88fcc24470d73ed4360e910f8549718b913ba56fb8775d9ef929a647835dfea",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/8e/33/6874185b791c71684c401fc74abd71bbdb102e8ee41c8f380cf25af41d29/coverage-7.17.2-cp314-cp314t-win32.whl",
        hash = "sha256:2c42c222939b8699e7bc0e453149627f211ebbbb2f74c1a04331b0cd9834e2c8",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/16/e0/9057b4cf962ca6089b144f0d93a748f5e2d13876dd0f33f9d5a2c2ec49d2/coverage-7.17.2-cp314-cp314t-win_amd64.whl",
        hash = "sha256:b94c509e26603ba7f8cb1bf8bb63967c7be533493be5668d8442cd06ec853d76",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/5e/4f/bd626297c942380279dff323e1d8a8937990d553119a4f887358488b1b54/coverage-7.17.2-cp314-cp314t-win_arm64.whl",
        hash = "sha256:eca90e028932de597e2c50f454ad8cc631281e14d20b9f801a649ab555deb580",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ac/92/ff8badc05ff0c4ed26ca62fb3d155e9014ff65768b76d5f399e63d9e9a79/coverage-7.17.2-cp315-cp315-android_24_arm64_v8a.whl",
        hash = "sha256:cbf751ae86ef0d80e719915c087b05776c8d9300141f6c3e56f536d78a62c301",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/5a/8b/c5a5392e5a5dceb68f3b1b8cdba925c7997699f351d811cd4a41add9c29e/coverage-7.17.2-cp315-cp315-android_24_x86_64.whl",
        hash = "sha256:249c4b4eaac9ced6fb85e465027ca26348111c2760108fffc356a16be4f54cd9",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/7b/bc/9259a1fc49ad663861cbfb3df6a99d4c8f62a11b242a2db3358822d28b17/coverage-7.17.2-cp315-cp315-ios_13_0_arm64_iphoneos.whl",
        hash = "sha256:e2fd4e664a34854cae8db58ca6132fb7b5a7efc67b14233e797194bd0d63b6b0",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/20/ad/83f03da8ab846af246d4a47b651e5d90229a4c3314e31e8eecade63b378f/coverage-7.17.2-cp315-cp315-ios_13_0_arm64_iphonesimulator.whl",
        hash = "sha256:0712a43e39410aa567f2e85846490f8dd6c839820e7edef2142767c5c03162ba",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/f3/08/e110687f24245edbbe9c0986a6ccd04f1f9a6e90e329cbd4347e2b81d76e/coverage-7.17.2-cp315-cp315-macosx_10_15_x86_64.whl",
        hash = "sha256:298849ca0e385767096995cb57f72059b469f43f9927b8393f29d134f7bb1062",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/93/24/7cfcd6adb4a0c18a10de12fd695edbf8cd121fdca0a6a63cea1bffc029fe/coverage-7.17.2-cp315-cp315-macosx_11_0_arm64.whl",
        hash = "sha256:81a432793440edef268dbadd493393bd6f70fa4b87f76c58114f7f77f1ccfaea",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/54/7a/af167a0bb6d0564209d35c8039b290327ecf7b3e34f838f9360b56d3a03c/coverage-7.17.2-cp315-cp315-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:d14872ccef35972c4ac290f2432f43d0a7bb230cae2b5ed26871ab86221e8b5f",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/f5/c6/4f3931c3ff80a6f2608209181adb00527970a4b43b64c3aa323383c37d51/coverage-7.17.2-cp315-cp315-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:3bd065e75c077d6de8cd3fe68699a8b47be3ec595af6b66e3629926839094609",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/3e/71/31a4945459008952061147ea9b85853902507d865a7272a9f64be0c4a093/coverage-7.17.2-cp315-cp315-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:8d3626b9816f7eadd0993c3703a1d8ed124b579cebe5201b446f1c0d551fa245",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/82/6b/a4eb258b0373034f8f19aeea4c1bc4c89942b5b228812ee9952f033dc611/coverage-7.17.2-cp315-cp315-manylinux2014_ppc64le.manylinux_2_17_ppc64le.manylinux_2_28_ppc64le.whl",
        hash = "sha256:c9639c2ea019c948b52067a0f74485039eb84b7a2de828ba6d178e663fb2b8bd",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/02/ae/9410f2f4bbaa698ff3869c7c09e0fa10d74482a1ec8040063157612f07a0/coverage-7.17.2-cp315-cp315-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:19d508b0611486f8e23e28abcba77795ee865ff0e0cd936349ba692c8d0d8ca4",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ad/ee/97549ec1bdf6ff6d17612dbcf4b2205daa74510273ac1efd1460e3db275c/coverage-7.17.2-cp315-cp315-musllinux_1_2_aarch64.whl",
        hash = "sha256:cfe64d2501806a04507217852a3132a9a9076321435500bf3b11943a5c872732",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/36/72/76e04605522a6dd81bbf43e1b407ca611f415c04b67e18c123ee440b1d69/coverage-7.17.2-cp315-cp315-musllinux_1_2_i686.whl",
        hash = "sha256:4274acd35aae5bbbd0908792260819b9720b171ccc099a8168f7c20ef5d6ab3a",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/30/8d/163e027635790ab232f3ec0261d2a26bec34c377bea2096554261444d0f5/coverage-7.17.2-cp315-cp315-musllinux_1_2_ppc64le.whl",
        hash = "sha256:85bccf6fe19ea3747147387971465f6a06197d6b9f6b644a97ba90ca5b09c5cd",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/18/35/11dd585a06be350285d42c17aa2fccd0af18d962b6979f03dd1a258eb705/coverage-7.17.2-cp315-cp315-musllinux_1_2_riscv64.whl",
        hash = "sha256:d5024913651813801fd43b65b6409b0d50f8bae95316c8f1512dfbd8ca96cb1f",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/1a/ed/f1f3b4bf6081122bf1820b1f38352377a75a2d5f39bb6331598e165b64af/coverage-7.17.2-cp315-cp315-musllinux_1_2_x86_64.whl",
        hash = "sha256:99b64a12fe6017c254a8027790e0eaa22eaeec201e7dfda5eaac176a6984ef27",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ab/bb/61e07a606a9f4d0f5391ac9b62b1f008a997f87860ad233f99833fd6e6bd/coverage-7.17.2-cp315-cp315-win32.whl",
        hash = "sha256:74d91af590514dda16165d5d7cfa94183150c6a6a80a99f61068369ae3959455",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/86/40/2d4980d3374a023a34c5ea7cd5d2b93c02c5588a324ca7faf8a0a8c7dbac/coverage-7.17.2-cp315-cp315-win_amd64.whl",
        hash = "sha256:075566a44289afb634ceaafa7d8d377bb2667a5b4a90fbee2609efdcd015c66e",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/f8/c8/b307327b1256f9ed8ffc3271db041913835cfee065fbaf45105978093c08/coverage-7.17.2-cp315-cp315-win_arm64.whl",
        hash = "sha256:be699e76b57fede8920a0f568eff23b270d9004414b7cf6744bdda851638be6e",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/40/18/0912e37f23c101faebd7c5e544c6ba6bd750715f81f2a2c7ea66f83a2295/coverage-7.17.2-cp315-cp315t-macosx_10_15_x86_64.whl",
        hash = "sha256:ffbaadf8612781358b3f949ad68dce26c5a35beaafcc48125fc231dbcce7d362",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/5e/a0/c4ce9bbf82b2e9dbf2e0326004c8c37d87a275f515fc7bb22344a6162050/coverage-7.17.2-cp315-cp315t-macosx_11_0_arm64.whl",
        hash = "sha256:d4004fce7b3a8ae5ef2af835670763f12723e9b9d74837697607b89a17f77312",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/3f/05/9c7429c87589534755398a58fe9837fdb2870a22d99e87623fcb261e1d4e/coverage-7.17.2-cp315-cp315t-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:a838a10afb5b60a6cc6315348b176badaf2409d821208a3e3cda1dc608129e23",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/e9/22/d1ad2ea7c8871d66f8453d33cdeec39986e6e1f2a104628e9bcb171f0209/coverage-7.17.2-cp315-cp315t-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:0fc17882975fe485cfc95fb2f20eed937e05e0c0d8ffa5048857cda3aa838e8a",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/0d/1d/5038de4bf6549903ec3d86959c6f18aff54911616b47aa96f4d6a5660c93/coverage-7.17.2-cp315-cp315t-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:a65faa1ee98e090a5fd7c116f6d3ab5c6a85fcc46849b8494835608715836399",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/8b/ea/68a26b4b5eb255d92de906fd66e8d720b1df15e705949ea9a9cef2cc7f8b/coverage-7.17.2-cp315-cp315t-manylinux2014_ppc64le.manylinux_2_17_ppc64le.manylinux_2_28_ppc64le.whl",
        hash = "sha256:7c17f716c837db550a202e7732cdfaa726b8515cba88be42193616913970d223",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/70/86/0f4238f09b22bc03a907346fabcabe5449626879cdedbc1edd362ab0e570/coverage-7.17.2-cp315-cp315t-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:545ca42488c7f0e62324fb2621aa05737db843b75e84e65a271bbf976f496f66",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/f1/ac/1885255425900f691c543d88394d9f0dacd2f2dc78422e660c747ca9c95c/coverage-7.17.2-cp315-cp315t-musllinux_1_2_aarch64.whl",
        hash = "sha256:8de787f533b13aeeea5d7139610eadb56f249cc739840b973603d1d18d0fb023",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/02/d6/0111601342d91e25d13e22a55f34600aa387c55b5027b90e78d941911821/coverage-7.17.2-cp315-cp315t-musllinux_1_2_i686.whl",
        hash = "sha256:485b2ed9e13b7e9209276843d7147e2f1cd1c816582655650a64c8f922093c58",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/70/48/d9bdc5346a9ad09711f55b6901ee05b57305e6b2b66e6edfd50f81f0d410/coverage-7.17.2-cp315-cp315t-musllinux_1_2_ppc64le.whl",
        hash = "sha256:a472e23a7514478e1c8124ea056424d681e3173975650b0a06b6181658f1009a",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/98/75/3a4d8ce4aa59ed2e898364acf923b39471689d51876bb978c42e664cdb79/coverage-7.17.2-cp315-cp315t-musllinux_1_2_riscv64.whl",
        hash = "sha256:0a623de5c57c5c3f3aed830c73a3a5aad91dbf76d53bc30ec161be758c8ca408",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/4a/11/d15082e504e7852a25848ee0dcb59453579ec923c6d1f3010316e1fb6118/coverage-7.17.2-cp315-cp315t-musllinux_1_2_x86_64.whl",
        hash = "sha256:2ad189c65706306644399e48530ad1aea1dfb311bd21d988df1ace422d09f3f8",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/f1/9d/6460101b0191afae9ed84c8d8136cc8cc09675f376ce08acb3118b8c27be/coverage-7.17.2-cp315-cp315t-win32.whl",
        hash = "sha256:6fd6f218e39a621a30dbaf9543831fa10fe713afc8a44b52fc42cfe277412609",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/9a/f2/3462d9616445a8cb36ec2e027d1c0ae82f6f90f224d9851ba0b22b7425d6/coverage-7.17.2-cp315-cp315t-win_amd64.whl",
        hash = "sha256:ef07aae0a666ef5edcab5bc1bb590468c6f4120a8cdad50a010d042a59ab6e77",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/4c/06/abeca0cf853e77aba9464d4ada4603c8b6e744b667c13e1d4eefecc487af/coverage-7.17.2-cp315-cp315t-win_arm64.whl",
        hash = "sha256:c68f64d96857749a215657c172f7144ed026063489686b901774f271997923c2",
        marker = "python_full_version >= '3.11'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/da/91/1805cc144497d76a436f66a21fa57492bee7ed1257826fb992f03b9b2b6f/coverage-7.17.2-py3-none-any.whl",
        hash = "sha256:e674027ceb6bfd959f1bb035000fd20fa8b717dc6765adaaf8bca347822c8c7d",
        marker = "python_full_version >= '3.11'",
    ),
]
# END: maintained by 'bazel run //dev/update_deps:update_coverage_deps <version>'

_coverage_patch = Label("//python/private:coverage.patch")

def select_coverage_whl(*, python_version, platform):
    """Select the coverage wheel compatible with the given toolchain.

    Args:
        python_version: The full python version.
        platform: The platform, which can be found in //python:versions.bzl PLATFORMS dict.

    Returns:
        A struct with `filename`, `url` and `sha256` attributes of the best
        matching wheel from `_coverage_wheels`.
    """
    target_platform = python_toolchain_platform(
        python_version = python_version,
        platform_name = platform,
    )

    whls = []
    for whl in _coverage_wheels:
        marker = getattr(whl, "marker", "")
        if marker and not evaluate(marker, env = target_platform.env):
            continue

        algo, _, digest = whl.hash.partition(":")
        if algo != "sha256":
            fail("BUG: unsupported hash algorithm '{}' for {}".format(algo, whl.url))

        whls.append(struct(
            filename = whl.url.rpartition("/")[2],
            url = whl.url,
            sha256 = digest,
        ))

    whl = select_whl(
        whls = whls,
        python_version = python_version,
        implementation_name = target_platform.env["implementation_name"],
        whl_platform_tags = target_platform.whl_platform_tags,
        whl_abi_tags = target_platform.whl_abi_tags,
        logger = repo_utils.logger(name = "coverage_dep", verbosity_level = "WARN"),
    )
    if not whl:
        fail("BUG: could not find a coverage wheel for {} and {}".format(python_version, platform))

    return whl

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
        # upstream coverage wrapper is written in shell.
        return None

    whl = select_coverage_whl(python_version = python_version, platform = platform)

    # NOTE @aignas 2026-07-27: if the default is matched, then the same file may be extracted
    # multiple times. The wheel is small enough to not matter in most cases.

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
        sha256 = whl.sha256,
        type = "zip",
        urls = [whl.url],
    )

    return "@{name}//:coverage".format(name = name)

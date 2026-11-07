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

# The wheels below were generated with:
#
#   bazel run //dev/update_deps:update_coverage_deps -- \
#       "7.10.7; python_full_version < '3.15'" \
#       "7.17.0; python_full_version >= '3.15'"
#
# Newer coverage versions do not support older python versions, so each version
# has a `python_full_version` marker for when it should be used.
# START: maintained by 'bazel run //dev/update_deps:update_coverage_deps <version>'
_coverage_wheels = [
    struct(
        url = "https://files.pythonhosted.org/packages/e5/6c/3a3f7a46888e69d18abe3ccc6fe4cb16cccb1e6a2f99698931dafca489e6/coverage-7.10.7-cp310-cp310-macosx_10_9_x86_64.whl",
        hash = "sha256:fc04cc7a3db33664e0c2d10eb8990ff6b3536f6842c9590ae8da4c614b9ed05a",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/03/94/952d30f180b1a916c11a56f5c22d3535e943aa22430e9e3322447e520e1c/coverage-7.10.7-cp310-cp310-macosx_11_0_arm64.whl",
        hash = "sha256:e201e015644e207139f7e2351980feb7040e6f4b2c2978892f3e3789d1c125e5",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/50/2b/9e0cf8ded1e114bcd8b2fd42792b57f1c4e9e4ea1824cde2af93a67305be/coverage-7.10.7-cp310-cp310-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:240af60539987ced2c399809bd34f7c78e8abe0736af91c3d7d0e795df633d17",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/19/20/d0384ac06a6f908783d9b6aa6135e41b093971499ec488e47279f5b846e6/coverage-7.10.7-cp310-cp310-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:8421e088bc051361b01c4b3a50fd39a4b9133079a2229978d9d30511fd05231b",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/60/83/5c283cff3d41285f8eab897651585db908a909c572bdc014bcfaf8a8b6ae/coverage-7.10.7-cp310-cp310-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:6be8ed3039ae7f7ac5ce058c308484787c86e8437e72b30bf5e88b8ea10f3c87",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/60/22/02eb98fdc5ff79f423e990d877693e5310ae1eab6cb20ae0b0b9ac45b23b/coverage-7.10.7-cp310-cp310-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:e28299d9f2e889e6d51b1f043f58d5f997c373cc12e6403b90df95b8b047c13e",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/b4/bc/25c83bcf3ad141b32cd7dc45485ef3c01a776ca3aa8ef0a93e77e8b5bc43/coverage-7.10.7-cp310-cp310-musllinux_1_2_aarch64.whl",
        hash = "sha256:c4e16bd7761c5e454f4efd36f345286d6f7c5fa111623c355691e2755cae3b9e",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/3c/b7/95574702888b58c0928a6e982038c596f9c34d52c5e5107f1eef729399b5/coverage-7.10.7-cp310-cp310-musllinux_1_2_i686.whl",
        hash = "sha256:b1c81d0e5e160651879755c9c675b974276f135558cf4ba79fee7b8413a515df",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/47/b6/40095c185f235e085df0e0b158f6bd68cc6e1d80ba6c7721dc81d97ec318/coverage-7.10.7-cp310-cp310-musllinux_1_2_riscv64.whl",
        hash = "sha256:606cc265adc9aaedcc84f1f064f0e8736bc45814f15a357e30fca7ecc01504e0",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/c8/50/4aea0556da7a4b93ec9168420d170b55e2eb50ae21b25062513d020c6861/coverage-7.10.7-cp310-cp310-musllinux_1_2_x86_64.whl",
        hash = "sha256:10b24412692df990dbc34f8fb1b6b13d236ace9dfdd68df5b28c2e39cafbba13",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/6a/28/ea1a84a60828177ae3b100cb6723838523369a44ec5742313ed7db3da160/coverage-7.10.7-cp310-cp310-win32.whl",
        hash = "sha256:b51dcd060f18c19290d9b8a9dd1e0181538df2ce0717f562fff6cf74d9fc0b5b",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/fc/1a/a81d46bbeb3c3fd97b9602ebaa411e076219a150489bcc2c025f151bd52d/coverage-7.10.7-cp310-cp310-win_amd64.whl",
        hash = "sha256:3a622ac801b17198020f09af3eaf45666b344a0d69fc2a6ffe2ea83aeef1d807",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/d2/5d/c1a17867b0456f2e9ce2d8d4708a4c3a089947d0bec9c66cdf60c9e7739f/coverage-7.10.7-cp311-cp311-macosx_10_9_x86_64.whl",
        hash = "sha256:a609f9c93113be646f44c2a0256d6ea375ad047005d7f57a5c15f614dc1b2f59",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/54/f0/514dcf4b4e3698b9a9077f084429681bf3aad2b4a72578f89d7f643eb506/coverage-7.10.7-cp311-cp311-macosx_11_0_arm64.whl",
        hash = "sha256:65646bb0359386e07639c367a22cf9b5bf6304e8630b565d0626e2bdf329227a",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/20/f6/9626b81d17e2a4b25c63ac1b425ff307ecdeef03d67c9a147673ae40dc36/coverage-7.10.7-cp311-cp311-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:5f33166f0dfcce728191f520bd2692914ec70fac2713f6bf3ce59c3deacb4699",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/b0/ef/bd8e719c2f7417ba03239052e099b76ea1130ac0cbb183ee1fcaa58aaff3/coverage-7.10.7-cp311-cp311-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:35f5e3f9e455bb17831876048355dca0f758b6df22f49258cb5a91da23ef437d",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a5/b6/bf054de41ec948b151ae2b79a55c107f5760979538f5fb80c195f2517718/coverage-7.10.7-cp311-cp311-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:4da86b6d62a496e908ac2898243920c7992499c1712ff7c2b6d837cc69d9467e",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/0f/e5/3860756aa6f9318227443c6ce4ed7bf9e70bb7f1447a0353f45ac5c7974b/coverage-7.10.7-cp311-cp311-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:6b8b09c1fad947c84bbbc95eca841350fad9cbfa5a2d7ca88ac9f8d836c92e23",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/26/0f/bd08bd042854f7fd07b45808927ebcce99a7ed0f2f412d11629883517ac2/coverage-7.10.7-cp311-cp311-musllinux_1_2_aarch64.whl",
        hash = "sha256:4376538f36b533b46f8971d3a3e63464f2c7905c9800db97361c43a2b14792ab",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/8e/a7/4777b14de4abcc2e80c6b1d430f5d51eb18ed1d75fca56cbce5f2db9b36e/coverage-7.10.7-cp311-cp311-musllinux_1_2_i686.whl",
        hash = "sha256:121da30abb574f6ce6ae09840dae322bef734480ceafe410117627aa54f76d82",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/34/72/17d082b00b53cd45679bad682fac058b87f011fd8b9fe31d77f5f8d3a4e4/coverage-7.10.7-cp311-cp311-musllinux_1_2_riscv64.whl",
        hash = "sha256:88127d40df529336a9836870436fc2751c339fbaed3a836d42c93f3e4bd1d0a2",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/81/7a/92367572eb5bdd6a84bfa278cc7e97db192f9f45b28c94a9ca1a921c3577/coverage-7.10.7-cp311-cp311-musllinux_1_2_x86_64.whl",
        hash = "sha256:ba58bbcd1b72f136080c0bccc2400d66cc6115f3f906c499013d065ac33a4b61",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/2f/88/a23cc185f6a805dfc4fdf14a94016835eeb85e22ac3a0e66d5e89acd6462/coverage-7.10.7-cp311-cp311-win32.whl",
        hash = "sha256:972b9e3a4094b053a4e46832b4bc829fc8a8d347160eb39d03f1690316a99c14",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/fe/ef/0b510a399dfca17cec7bc2f05ad8bd78cf55f15c8bc9a73ab20c5c913c2e/coverage-7.10.7-cp311-cp311-win_amd64.whl",
        hash = "sha256:a7b55a944a7f43892e28ad4bc0561dfd5f0d73e605d1aa5c3c976b52aea121d2",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/51/7f/023657f301a276e4ba1850f82749bc136f5a7e8768060c2e5d9744a22951/coverage-7.10.7-cp311-cp311-win_arm64.whl",
        hash = "sha256:736f227fb490f03c6488f9b6d45855f8e0fd749c007f9303ad30efab0e73c05a",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/13/e4/eb12450f71b542a53972d19117ea5a5cea1cab3ac9e31b0b5d498df1bd5a/coverage-7.10.7-cp312-cp312-macosx_10_13_x86_64.whl",
        hash = "sha256:7bb3b9ddb87ef7725056572368040c32775036472d5a033679d1fa6c8dc08417",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/37/66/593f9be12fc19fb36711f19a5371af79a718537204d16ea1d36f16bd78d2/coverage-7.10.7-cp312-cp312-macosx_11_0_arm64.whl",
        hash = "sha256:18afb24843cbc175687225cab1138c95d262337f5473512010e46831aa0c2973",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/66/80/4c49f7ae09cafdacc73fbc30949ffe77359635c168f4e9ff33c9ebb07838/coverage-7.10.7-cp312-cp312-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:399a0b6347bcd3822be369392932884b8216d0944049ae22925631a9b3d4ba4c",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a6/90/a64aaacab3b37a17aaedd83e8000142561a29eb262cede42d94a67f7556b/coverage-7.10.7-cp312-cp312-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:314f2c326ded3f4b09be11bc282eb2fc861184bc95748ae67b360ac962770be7",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/98/2e/2dda59afd6103b342e096f246ebc5f87a3363b5412609946c120f4e7750d/coverage-7.10.7-cp312-cp312-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:c41e71c9cfb854789dee6fc51e46743a6d138b1803fab6cb860af43265b42ea6",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/53/dc/8d8119c9051d50f3119bb4a75f29f1e4a6ab9415cd1fa8bf22fcc3fb3b5f/coverage-7.10.7-cp312-cp312-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:bc01f57ca26269c2c706e838f6422e2a8788e41b3e3c65e2f41148212e57cd59",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/98/b3/edaff9c5d79ee4d4b6d3fe046f2b1d799850425695b789d491a64225d493/coverage-7.10.7-cp312-cp312-musllinux_1_2_aarch64.whl",
        hash = "sha256:a6442c59a8ac8b85812ce33bc4d05bde3fb22321fa8294e2a5b487c3505f611b",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/11/25/9a0728564bb05863f7e513e5a594fe5ffef091b325437f5430e8cfb0d530/coverage-7.10.7-cp312-cp312-musllinux_1_2_i686.whl",
        hash = "sha256:78a384e49f46b80fb4c901d52d92abe098e78768ed829c673fbb53c498bef73a",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/e0/fd/ca2650443bfbef5b0e74373aac4df67b08180d2f184b482c41499668e258/coverage-7.10.7-cp312-cp312-musllinux_1_2_riscv64.whl",
        hash = "sha256:5e1e9802121405ede4b0133aa4340ad8186a1d2526de5b7c3eca519db7bb89fb",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/24/79/f692f125fb4299b6f963b0745124998ebb8e73ecdfce4ceceb06a8c6bec5/coverage-7.10.7-cp312-cp312-musllinux_1_2_x86_64.whl",
        hash = "sha256:d41213ea25a86f69efd1575073d34ea11aabe075604ddf3d148ecfec9e1e96a1",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/5e/75/61b9bbd6c7d24d896bfeec57acba78e0f8deac68e6baf2d4804f7aae1f88/coverage-7.10.7-cp312-cp312-win32.whl",
        hash = "sha256:77eb4c747061a6af8d0f7bdb31f1e108d172762ef579166ec84542f711d90256",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ca/f3/3bf7905288b45b075918d372498f1cf845b5b579b723c8fd17168018d5f5/coverage-7.10.7-cp312-cp312-win_amd64.whl",
        hash = "sha256:f51328ffe987aecf6d09f3cd9d979face89a617eacdaea43e7b3080777f647ba",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/5c/44/3e32dbe933979d05cf2dac5e697c8599cfe038aaf51223ab901e208d5a62/coverage-7.10.7-cp312-cp312-win_arm64.whl",
        hash = "sha256:bda5e34f8a75721c96085903c6f2197dc398c20ffd98df33f866a9c8fd95f4bf",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/9a/94/b765c1abcb613d103b64fcf10395f54d69b0ef8be6a0dd9c524384892cc7/coverage-7.10.7-cp313-cp313-macosx_10_13_x86_64.whl",
        hash = "sha256:981a651f543f2854abd3b5fcb3263aac581b18209be49863ba575de6edf4c14d",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/72/4f/732fff31c119bb73b35236dd333030f32c4bfe909f445b423e6c7594f9a2/coverage-7.10.7-cp313-cp313-macosx_11_0_arm64.whl",
        hash = "sha256:73ab1601f84dc804f7812dc297e93cd99381162da39c47040a827d4e8dafe63b",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/87/02/ae7e0af4b674be47566707777db1aa375474f02a1d64b9323e5813a6cdd5/coverage-7.10.7-cp313-cp313-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:a8b6f03672aa6734e700bbcd65ff050fd19cddfec4b031cc8cf1c6967de5a68e",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a2/77/8c6d22bf61921a59bce5471c2f1f7ac30cd4ac50aadde72b8c48d5727902/coverage-7.10.7-cp313-cp313-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:10b6ba00ab1132a0ce4428ff68cf50a25efd6840a42cdf4239c9b99aad83be8b",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/b1/20/b6ea4f69bbb52dac0aebd62157ba6a9dddbfe664f5af8122dac296c3ee15/coverage-7.10.7-cp313-cp313-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:c79124f70465a150e89340de5963f936ee97097d2ef76c869708c4248c63ca49",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/f9/28/4831523ba483a7f90f7b259d2018fef02cb4d5b90bc7c1505d6e5a84883c/coverage-7.10.7-cp313-cp313-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:69212fbccdbd5b0e39eac4067e20a4a5256609e209547d86f740d68ad4f04911",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a7/9f/4331142bc98c10ca6436d2d620c3e165f31e6c58d43479985afce6f3191c/coverage-7.10.7-cp313-cp313-musllinux_1_2_aarch64.whl",
        hash = "sha256:7ea7c6c9d0d286d04ed3541747e6597cbe4971f22648b68248f7ddcd329207f0",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ce/60/bda83b96602036b77ecf34e6393a3836365481b69f7ed7079ab85048202b/coverage-7.10.7-cp313-cp313-musllinux_1_2_i686.whl",
        hash = "sha256:b9be91986841a75042b3e3243d0b3cb0b2434252b977baaf0cd56e960fe1e46f",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/5f/af/152633ff35b2af63977edd835d8e6430f0caef27d171edf2fc76c270ef31/coverage-7.10.7-cp313-cp313-musllinux_1_2_riscv64.whl",
        hash = "sha256:b281d5eca50189325cfe1f365fafade89b14b4a78d9b40b05ddd1fc7d2a10a9c",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/9d/71/d92105d122bd21cebba877228990e1646d862e34a98bb3374d3fece5a794/coverage-7.10.7-cp313-cp313-musllinux_1_2_x86_64.whl",
        hash = "sha256:99e4aa63097ab1118e75a848a28e40d68b08a5e19ce587891ab7fd04475e780f",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a2/9e/9fdb08f4bf476c912f0c3ca292e019aab6712c93c9344a1653986c3fd305/coverage-7.10.7-cp313-cp313-win32.whl",
        hash = "sha256:dc7c389dce432500273eaf48f410b37886be9208b2dd5710aaf7c57fd442c698",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/b1/b1/a75fd25df44eab52d1931e89980d1ada46824c7a3210be0d3c88a44aaa99/coverage-7.10.7-cp313-cp313-win_amd64.whl",
        hash = "sha256:cac0fdca17b036af3881a9d2729a850b76553f3f716ccb0360ad4dbc06b3b843",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/14/3a/d720d7c989562a6e9a14b2c9f5f2876bdb38e9367126d118495b89c99c37/coverage-7.10.7-cp313-cp313-win_arm64.whl",
        hash = "sha256:4b6f236edf6e2f9ae8fcd1332da4e791c1b6ba0dc16a2dc94590ceccb482e546",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/bb/22/e04514bf2a735d8b0add31d2b4ab636fc02370730787c576bb995390d2d5/coverage-7.10.7-cp313-cp313t-macosx_10_13_x86_64.whl",
        hash = "sha256:a0ec07fd264d0745ee396b666d47cef20875f4ff2375d7c4f58235886cc1ef0c",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/11/0b/91128e099035ece15da3445d9015e4b4153a6059403452d324cbb0a575fa/coverage-7.10.7-cp313-cp313t-macosx_11_0_arm64.whl",
        hash = "sha256:dd5e856ebb7bfb7672b0086846db5afb4567a7b9714b8a0ebafd211ec7ce6a15",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/8b/51/66420081e72801536a091a0c8f8c1f88a5c4bf7b9b1bdc6222c7afe6dc9b/coverage-7.10.7-cp313-cp313t-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:f57b2a3c8353d3e04acf75b3fed57ba41f5c0646bbf1d10c7c282291c97936b4",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/5d/22/9b8d458c2881b22df3db5bb3e7369e63d527d986decb6c11a591ba2364f7/coverage-7.10.7-cp313-cp313t-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:1ef2319dd15a0b009667301a3f84452a4dc6fddfd06b0c5c53ea472d3989fbf0",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/f7/08/16bee2c433e60913c610ea200b276e8eeef084b0d200bdcff69920bd5828/coverage-7.10.7-cp313-cp313t-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:83082a57783239717ceb0ad584de3c69cf581b2a95ed6bf81ea66034f00401c0",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/20/9d/e53eb9771d154859b084b90201e5221bca7674ba449a17c101a5031d4054/coverage-7.10.7-cp313-cp313t-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:50aa94fb1fb9a397eaa19c0d5ec15a5edd03a47bf1a3a6111a16b36e190cff65",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ad/b0/69bc7050f8d4e56a89fb550a1577d5d0d1db2278106f6f626464067b3817/coverage-7.10.7-cp313-cp313t-musllinux_1_2_aarch64.whl",
        hash = "sha256:2120043f147bebb41c85b97ac45dd173595ff14f2a584f2963891cbcc3091541",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ef/4b/2514b060dbd1bc0aaf23b852c14bb5818f244c664cb16517feff6bb3a5ab/coverage-7.10.7-cp313-cp313t-musllinux_1_2_i686.whl",
        hash = "sha256:2fafd773231dd0378fdba66d339f84904a8e57a262f583530f4f156ab83863e6",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/54/78/7ba2175007c246d75e496f64c06e94122bdb914790a1285d627a918bd271/coverage-7.10.7-cp313-cp313t-musllinux_1_2_riscv64.whl",
        hash = "sha256:0b944ee8459f515f28b851728ad224fa2d068f1513ef6b7ff1efafeb2185f999",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/c0/b3/fac9f7abbc841409b9a410309d73bfa6cfb2e51c3fada738cb607ce174f8/coverage-7.10.7-cp313-cp313t-musllinux_1_2_x86_64.whl",
        hash = "sha256:4b583b97ab2e3efe1b3e75248a9b333bd3f8b0b1b8e5b45578e05e5850dfb2c2",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ee/51/a03bec00d37faaa891b3ff7387192cef20f01604e5283a5fabc95346befa/coverage-7.10.7-cp313-cp313t-win32.whl",
        hash = "sha256:2a78cd46550081a7909b3329e2266204d584866e8d97b898cd7fb5ac8d888b1a",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/53/22/3cf25d614e64bf6d8e59c7c669b20d6d940bb337bdee5900b9ca41c820bb/coverage-7.10.7-cp313-cp313t-win_amd64.whl",
        hash = "sha256:33a5e6396ab684cb43dc7befa386258acb2d7fae7f67330ebb85ba4ea27938eb",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/49/a1/00164f6d30d8a01c3c9c48418a7a5be394de5349b421b9ee019f380df2a0/coverage-7.10.7-cp313-cp313t-win_arm64.whl",
        hash = "sha256:86b0e7308289ddde73d863b7683f596d8d21c7d8664ce1dee061d0bcf3fbb4bb",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/23/9c/5844ab4ca6a4dd97a1850e030a15ec7d292b5c5cb93082979225126e35dd/coverage-7.10.7-cp314-cp314-macosx_10_13_x86_64.whl",
        hash = "sha256:b06f260b16ead11643a5a9f955bd4b5fd76c1a4c6796aeade8520095b75de520",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/f0/89/673f6514b0961d1f0e20ddc242e9342f6da21eaba3489901b565c0689f34/coverage-7.10.7-cp314-cp314-macosx_11_0_arm64.whl",
        hash = "sha256:212f8f2e0612778f09c55dd4872cb1f64a1f2b074393d139278ce902064d5b32",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/05/e8/261cae479e85232828fb17ad536765c88dd818c8470aca690b0ac6feeaa3/coverage-7.10.7-cp314-cp314-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:3445258bcded7d4aa630ab8296dea4d3f15a255588dd535f980c193ab6b95f3f",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/82/62/14ed6546d0207e6eda876434e3e8475a3e9adbe32110ce896c9e0c06bb9a/coverage-7.10.7-cp314-cp314-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:bb45474711ba385c46a0bfe696c695a929ae69ac636cda8f532be9e8c93d720a",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ff/49/07f00db9ac6478e4358165a08fb41b469a1b053212e8a00cb02f0d27a05f/coverage-7.10.7-cp314-cp314-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:813922f35bd800dca9994c5971883cbc0d291128a5de6b167c7aa697fcf59360",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a2/59/c5201c62dbf165dfbc91460f6dbbaa85a8b82cfa6131ac45d6c1bfb52deb/coverage-7.10.7-cp314-cp314-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:93c1b03552081b2a4423091d6fb3787265b8f86af404cff98d1b5342713bdd69",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/07/ae/5920097195291a51fb00b3a70b9bbd2edbfe3c84876a1762bd1ef1565ebc/coverage-7.10.7-cp314-cp314-musllinux_1_2_aarch64.whl",
        hash = "sha256:cc87dd1b6eaf0b848eebb1c86469b9f72a1891cb42ac7adcfbce75eadb13dd14",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/b9/3c/a815dde77a2981f5743a60b63df31cb322c944843e57dbd579326625a413/coverage-7.10.7-cp314-cp314-musllinux_1_2_i686.whl",
        hash = "sha256:39508ffda4f343c35f3236fe8d1a6634a51f4581226a1262769d7f970e73bffe",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/aa/99/f5cdd8421ea656abefb6c0ce92556709db2265c41e8f9fc6c8ae0f7824c9/coverage-7.10.7-cp314-cp314-musllinux_1_2_riscv64.whl",
        hash = "sha256:925a1edf3d810537c5a3abe78ec5530160c5f9a26b1f4270b40e62cc79304a1e",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/c3/7a/e9a2da6a1fc5d007dd51fca083a663ab930a8c4d149c087732a5dbaa0029/coverage-7.10.7-cp314-cp314-musllinux_1_2_x86_64.whl",
        hash = "sha256:2c8b9a0636f94c43cd3576811e05b89aa9bc2d0a85137affc544ae5cb0e4bfbd",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ef/5b/0b5799aa30380a949005a353715095d6d1da81927d6dbed5def2200a4e25/coverage-7.10.7-cp314-cp314-win32.whl",
        hash = "sha256:b7b8288eb7cdd268b0304632da8cb0bb93fadcfec2fe5712f7b9cc8f4d487be2",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/da/b0/e802fbb6eb746de006490abc9bb554b708918b6774b722bb3a0e6aa1b7de/coverage-7.10.7-cp314-cp314-win_amd64.whl",
        hash = "sha256:1ca6db7c8807fb9e755d0379ccc39017ce0a84dcd26d14b5a03b78563776f681",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/9e/e8/71d0c8e374e31f39e3389bb0bd19e527d46f00ea8571ec7ec8fd261d8b44/coverage-7.10.7-cp314-cp314-win_arm64.whl",
        hash = "sha256:097c1591f5af4496226d5783d036bf6fd6cd0cbc132e071b33861de756efb880",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/62/09/9a5608d319fa3eba7a2019addeacb8c746fb50872b57a724c9f79f146969/coverage-7.10.7-cp314-cp314t-macosx_10_13_x86_64.whl",
        hash = "sha256:a62c6ef0d50e6de320c270ff91d9dd0a05e7250cac2a800b7784bae474506e63",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/f5/6f/f58d46f33db9f2e3647b2d0764704548c184e6f5e014bef528b7f979ef84/coverage-7.10.7-cp314-cp314t-macosx_11_0_arm64.whl",
        hash = "sha256:9fa6e4dd51fe15d8738708a973470f67a855ca50002294852e9571cdbd9433f2",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/74/5c/183ffc817ba68e0b443b8c934c8795553eb0c14573813415bd59941ee165/coverage-7.10.7-cp314-cp314t-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:8fb190658865565c549b6b4706856d6a7b09302c797eb2cf8e7fe9dabb043f0d",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/0f/48/71a8abe9c1ad7e97548835e3cc1adbf361e743e9d60310c5f75c9e7bf847/coverage-7.10.7-cp314-cp314t-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:affef7c76a9ef259187ef31599a9260330e0335a3011732c4b9effa01e1cd6e0",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/84/fd/193a8fb132acfc0a901f72020e54be5e48021e1575bb327d8ee1097a28fd/coverage-7.10.7-cp314-cp314t-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:6e16e07d85ca0cf8bafe5f5d23a0b850064e8e945d5677492b06bbe6f09cc699",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/b1/8f/74ecc30607dd95ad50e3034221113ccb1c6d4e8085cc761134782995daae/coverage-7.10.7-cp314-cp314t-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:03ffc58aacdf65d2a82bbeb1ffe4d01ead4017a21bfd0454983b88ca73af94b9",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/0f/55/79ff53a769f20d71b07023ea115c9167c0bb56f281320520cf64c5298a96/coverage-7.10.7-cp314-cp314t-musllinux_1_2_aarch64.whl",
        hash = "sha256:1b4fd784344d4e52647fd7857b2af5b3fbe6c239b0b5fa63e94eb67320770e0f",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/88/e2/dac66c140009b61ac3fc13af673a574b00c16efdf04f9b5c740703e953c0/coverage-7.10.7-cp314-cp314t-musllinux_1_2_i686.whl",
        hash = "sha256:0ebbaddb2c19b71912c6f2518e791aa8b9f054985a0769bdb3a53ebbc765c6a1",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a2/f1/f48f645e3f33bb9ca8a496bc4a9671b52f2f353146233ebd7c1df6160440/coverage-7.10.7-cp314-cp314t-musllinux_1_2_riscv64.whl",
        hash = "sha256:a2d9a3b260cc1d1dbdb1c582e63ddcf5363426a1a68faa0f5da28d8ee3c722a0",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/bb/3b/8442618972c51a7affeead957995cfa8323c0c9bcf8fa5a027421f720ff4/coverage-7.10.7-cp314-cp314t-musllinux_1_2_x86_64.whl",
        hash = "sha256:a3cc8638b2480865eaa3926d192e64ce6c51e3d29c849e09d5b4ad95efae5399",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/b2/dc/101f3fa3a45146db0cb03f5b4376e24c0aac818309da23e2de0c75295a91/coverage-7.10.7-cp314-cp314t-win32.whl",
        hash = "sha256:67f8c5cbcd3deb7a60b3345dffc89a961a484ed0af1f6f73de91705cc6e31235",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/4c/a1/74c51803fc70a8a40d7346660379e144be772bab4ac7bb6e6b905152345c/coverage-7.10.7-cp314-cp314t-win_amd64.whl",
        hash = "sha256:e1ed71194ef6dea7ed2d5cb5f7243d4bcd334bfb63e59878519be558078f848d",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/12/65/f116a6d2127df30bcafbceef0302d8a64ba87488bf6f73a6d8eebf060873/coverage-7.10.7-cp314-cp314t-win_arm64.whl",
        hash = "sha256:7fe650342addd8524ca63d77b2362b02345e5f1a093266787d210c70a50b471a",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a3/ad/d1c25053764b4c42eb294aae92ab617d2e4f803397f9c7c8295caa77a260/coverage-7.10.7-cp39-cp39-macosx_10_9_x86_64.whl",
        hash = "sha256:fff7b9c3f19957020cac546c70025331113d2e61537f6e2441bc7657913de7d3",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/52/2f/b9f9daa39b80ece0b9548bbb723381e29bc664822d9a12c2135f8922c22b/coverage-7.10.7-cp39-cp39-macosx_11_0_arm64.whl",
        hash = "sha256:bc91b314cef27742da486d6839b677b3f2793dfe52b51bbbb7cf736d5c29281c",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/dd/6e/30d006c3b469e58449650642383dddf1c8fb63d44fdf92994bfd46570695/coverage-7.10.7-cp39-cp39-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:567f5c155eda8df1d3d439d40a45a6a5f029b429b06648235f1e7e51b522b396",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/b0/49/8a070782ce7e6b94ff6a0b6d7c65ba6bc3091d92a92cef4cd4eb0767965c/coverage-7.10.7-cp39-cp39-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:2af88deffcc8a4d5974cf2d502251bc3b2db8461f0b66d80a449c33757aa9f40",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/6a/92/1c1c5a9e8677ce56d42b97bdaca337b2d4d9ebe703d8c174ede52dbabd5f/coverage-7.10.7-cp39-cp39-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:c7315339eae3b24c2d2fa1ed7d7a38654cba34a13ef19fbcb9425da46d3dc594",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/c0/54/b140edee7257e815de7426d5d9846b58505dffc29795fff2dfb7f8a1c5a0/coverage-7.10.7-cp39-cp39-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:912e6ebc7a6e4adfdbb1aec371ad04c68854cd3bf3608b3514e7ff9062931d8a",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/e4/9e/6d6b8295940b118e8b7083b29226c71f6154f7ff41e9ca431f03de2eac0d/coverage-7.10.7-cp39-cp39-musllinux_1_2_aarch64.whl",
        hash = "sha256:f49a05acd3dfe1ce9715b657e28d138578bc40126760efb962322c56e9ca344b",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/db/e5/5e957ca747d43dbe4d9714358375c7546cb3cb533007b6813fc20fce37ad/coverage-7.10.7-cp39-cp39-musllinux_1_2_i686.whl",
        hash = "sha256:cce2109b6219f22ece99db7644b9622f54a4e915dad65660ec435e89a3ea7cc3",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/9a/45/540fc5cc92536a1b783b7ef99450bd55a4b3af234aae35a18a339973ce30/coverage-7.10.7-cp39-cp39-musllinux_1_2_riscv64.whl",
        hash = "sha256:f3c887f96407cea3916294046fc7dab611c2552beadbed4ea901cbc6a40cc7a0",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/75/0b/8287b2e5b38c8fe15d7e3398849bb58d382aedc0864ea0fa1820e8630491/coverage-7.10.7-cp39-cp39-musllinux_1_2_x86_64.whl",
        hash = "sha256:635adb9a4507c9fd2ed65f39693fa31c9a3ee3a8e6dc64df033e8fdf52a7003f",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/0c/1d/29724999984740f0c86d03e6420b942439bf5bd7f54d4382cae386a9d1e9/coverage-7.10.7-cp39-cp39-win32.whl",
        hash = "sha256:5a02d5a850e2979b0a014c412573953995174743a3f7fa4ea5a6e9a3c5617431",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/43/11/4b1e6b129943f905ca54c339f343877b55b365ae2558806c1be4f7476ed5/coverage-7.10.7-cp39-cp39-win_amd64.whl",
        hash = "sha256:c134869d5ffe34547d14e174c866fd8fe2254918cc0a95e99052903bc1543e07",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ec/16/114df1c291c22cac3b0c127a73e0af5c12ed7bbb6558d310429a0ae24023/coverage-7.10.7-py3-none-any.whl",
        hash = "sha256:f7941f6f2fe6dd6807a1208737b8a0cbcf1cc6d7b07d24998ad2d63590868260",
        marker = "python_full_version < '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/75/25/79a66272edd250031aeee6db87d500a0bf76390d0d5f8c2f431fe354715f/coverage-7.17.0-cp311-cp311-macosx_10_9_x86_64.whl",
        hash = "sha256:99a7b390cbccc6bf029ca4da3f0f607c218bb4085e9cd6b58a90d14ca12993c3",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/52/a6/f5f6fefb2fc1305363927edad1d0a60ce6ef80d6c1a74a79e825f0f670eb/coverage-7.17.0-cp311-cp311-macosx_11_0_arm64.whl",
        hash = "sha256:f72640e02a470b57b15cd655820133f6892760209283a363a60e2df932d5f0fe",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/28/61/72889bac8eb44c51f8043edb227df551dfdca1fc4819a6c6d67b3f69427b/coverage-7.17.0-cp311-cp311-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:2dc9233f39149b5a4f4aba17a4b6bc5cca22e52cfc4b06fdb07d014439b8b2ea",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/f4/e4/03e4a5644df9b73de0d44d1b82acd18b06c42b5abc3f1433be8363fa983d/coverage-7.17.0-cp311-cp311-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:8e8113d3852e9377421a61de1917df27b3abb25404a4ecf69f9e64612c4345b5",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/6f/4e/949022286df7e59e8633a3a7e6635e0e6b53af7d57074cb0bf8f500373fb/coverage-7.17.0-cp311-cp311-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:c86a39539d10d666bb819c16c94d7edfc1aa2e0531b937f7c549b83d15177c6e",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/27/cf/7d67f60df081006315699b7edb9402c1b47142caf1383f4e56ae8ff1a501/coverage-7.17.0-cp311-cp311-manylinux2014_ppc64le.manylinux_2_17_ppc64le.manylinux_2_28_ppc64le.whl",
        hash = "sha256:559f748446ee799803686b5784e3deb54c70d655ac386a860e06b11672504ba7",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/e1/e0/9293d94afbc099990a085e88229a51c79b00828aba0f2adda32dc4cc16d1/coverage-7.17.0-cp311-cp311-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:34d65c9e8e257f48a654908005046fbf1bc48d9540ae3776ad08c0acd010e10c",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/24/c8/bcd28efedf262c074dae76f61098739eb02b15f3f716f80cc86f9885b8a9/coverage-7.17.0-cp311-cp311-musllinux_1_2_aarch64.whl",
        hash = "sha256:5b7fa0997b8eba7378ac66f31ec7f70164490353ab79b9667d37c0d365e50177",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/b8/dc/503f55e5e2200933403c90d619d9f779b5060ddd338b1bdc63cd235592cb/coverage-7.17.0-cp311-cp311-musllinux_1_2_i686.whl",
        hash = "sha256:6ae0453a3390e67f7bfbe34417bbdf5b4ebfc21db23fb446a0a41115eeeca6ca",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/bb/b1/f1a57c36077cc516240636f7eff0d1427939ed795f096dd2c7769213a56c/coverage-7.17.0-cp311-cp311-musllinux_1_2_ppc64le.whl",
        hash = "sha256:96151262832f3c230ebae23b2d6911ad549e1738465946c97004913ff06112ba",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a8/4f/c2e59d4a132936c7c207b9b69ab99c0f27b14c3c93266e9922aa3b562b37/coverage-7.17.0-cp311-cp311-musllinux_1_2_riscv64.whl",
        hash = "sha256:cd7397de6cc782f00fe5ac1d75e9b306bcfa49c8b6b8dd6ed1f7709393ad40b3",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/05/04/50742c0ee8b6c85826ff11737c93ed957fea4c9acf4b4b99804bdac1dd84/coverage-7.17.0-cp311-cp311-musllinux_1_2_x86_64.whl",
        hash = "sha256:9d1fdf82c6fea57b5e9dada509f9ce9638c8334664e2c98c7f6f1ccf3d143ad2",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/8e/cd/83ad4bbbfcb6d045a33c14cdca313f6c9275737c67f3b7300222e3239a37/coverage-7.17.0-cp311-cp311-win32.whl",
        hash = "sha256:38c86e5d74bbfd88a393fa3f91257c1225c63aa6db6d5918de3e49ab04f91c6e",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ca/c8/dcc5a7effa79707eb8a61e699b141cff7c9b46036771274cfb48ea7b765f/coverage-7.17.0-cp311-cp311-win_amd64.whl",
        hash = "sha256:2ed3097c6817bc1a7fc8ae0a6131db74aa1150d863cccc308237ff362d3226b2",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/d1/58/a8553e0dcd38d8136df63964638d2b588e0a4a916bff1bca996244fda693/coverage-7.17.0-cp311-cp311-win_arm64.whl",
        hash = "sha256:6052e878b628abcd38fa5f2b64abebc686eed4e2267da42434017a9c6d24f241",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/0a/25/989fd3b495c4274ac0cf54cb6664326415e60183a7f8a73dd9bbb0b11e34/coverage-7.17.0-cp312-cp312-macosx_10_13_x86_64.whl",
        hash = "sha256:0cfdc938ca3319d873d1f1252e60620a39aee4ebf9dbd7cc58238109ebda9c51",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/db/cb/14726426bf3241657facbf0f7df7babd8f7d3fcf8e4609b7929f9dceecbc/coverage-7.17.0-cp312-cp312-macosx_11_0_arm64.whl",
        hash = "sha256:d523da3c2e4bca49417768bcdb1a443c5b359dc44b8b93a3102e118fce912c40",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/8e/97/f95ed32cd3cfbe261a3598e694cb770cefc7b2d13ff013418d6f70a44dde/coverage-7.17.0-cp312-cp312-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:adbf3450c0f3f2b2854e282a8758f2b3eddf787eeff24ec9c9bc2cbc38328cc1",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/91/ac/eb4c31f741509a9ef48cf6f28385e98e9de0785599282252eee252ff8af7/coverage-7.17.0-cp312-cp312-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:85932227e9dd38e62cd29c17fefdfecfb919eead6af1e3259522d03cf85de983",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/e8/3e/d9cd006d1a3cc5deab07beb29b86cb4a10dd84d66b330820363fb8d310d6/coverage-7.17.0-cp312-cp312-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:30f5477aac9c9e4a0a641c55f8f8fddd7f3bd91176c912c50f40ffced96b4034",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/c0/3a/4c872c6ae0762b09cdb8e856891bb3f584848cb60b6dda2bacb85fe2f3f0/coverage-7.17.0-cp312-cp312-manylinux2014_ppc64le.manylinux_2_17_ppc64le.manylinux_2_28_ppc64le.whl",
        hash = "sha256:0b8bb651a4406fb6a983a905309fec1783443c65e1771b41e92740a0f4a1176b",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/df/98/1d41a2373fa98b423bcd70adb91d75e38eafb417955426dbb920b10016f3/coverage-7.17.0-cp312-cp312-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:0edeb6594f080c8de1263cccb239cb316ef77aeb959e2e0f38f2953fcc72a49e",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/92/6a/fe04b5e63e76506daa63d90bdfb00a53767fe5df18546b437d6226918d6b/coverage-7.17.0-cp312-cp312-musllinux_1_2_aarch64.whl",
        hash = "sha256:da94ec0484e84fce5c7bf8d0f54b97767a90d992653a129b35634699d516e0a5",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/4f/c3/5c5a78dc19dd4799be9c6ec022316fb25ababaeacfaf0f52f24c56a57b43/coverage-7.17.0-cp312-cp312-musllinux_1_2_i686.whl",
        hash = "sha256:a25cc5e8c23a590815c6a7aa43624234d25cb23b21b484adb8a0daed59860db5",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ed/e7/4c1d8eaff4d756fefd15d58c4953a78ab656782fd0e32c5a3465dba61aa0/coverage-7.17.0-cp312-cp312-musllinux_1_2_ppc64le.whl",
        hash = "sha256:db645c81cf4d6bcb392ea1894aad65d55d1588a8472c834b25ca575da3029a56",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a6/2a/0b17c3e2e7b6ff1a5d92eb58915c0d1026668928f961d14dac73cf1b6096/coverage-7.17.0-cp312-cp312-musllinux_1_2_riscv64.whl",
        hash = "sha256:6a80a11b90c4a03df1502304cf24ff953255b6b5d076ef79066ecf88baaff31f",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/d3/2d/eb0cbde0535342df0d17a667163030a3afb67e5eb9e3ad94af9540041584/coverage-7.17.0-cp312-cp312-musllinux_1_2_x86_64.whl",
        hash = "sha256:e4eaf11d6b0f2147f46cfbf06fe7edcca6f095d0120da00ddc2458995ee869fc",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/2e/47/1be2a6db7eb655d0a1d899217c3f2469f9121cbbeddac35c1c8173b1482e/coverage-7.17.0-cp312-cp312-win32.whl",
        hash = "sha256:912a29f338798541d795e2e25903c6fe7a99dee70a40fe4706a9a124649b523e",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/11/c5/201c894c57de81875d8b8cc527ba222aa350e8cfb183eb3f6df45d06ad8e/coverage-7.17.0-cp312-cp312-win_amd64.whl",
        hash = "sha256:88a1a9fb0075b83389dd9b403bb3fce976031b3c2aa0e05e3e57143cf639de69",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/0b/5d/196095339b19758cf83f507fb598bc42820ae124745feb3084662729e17a/coverage-7.17.0-cp312-cp312-win_arm64.whl",
        hash = "sha256:2c680e838ff9e68d491158625ca2c1ddb17d78d791bba96a31f8b839b4990438",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/54/e6/1f01afbc9f4fa8ca5e1fa6fdf537a5c58b5765d1b4167ee284cddb9acc72/coverage-7.17.0-cp313-cp313-android_24_arm64_v8a.whl",
        hash = "sha256:84538c040f4e6214f663459d89372ce4e6b2bbdd9d397ef0dca7b3ecd56b8eb2",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/92/7a/bdb7e6260c4a211389aeac9b89dc31662ebe122153ad0ecfd156897912df/coverage-7.17.0-cp313-cp313-android_24_x86_64.whl",
        hash = "sha256:6abfb6a4cf1cb1b67bc8fccdde177e2d2b781d0d34449e7078156547025140e5",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/37/4e/276e7d5b3cfb124871bdb544c27b004a8b4e270e6bf8e7414149c54b5e5b/coverage-7.17.0-cp313-cp313-ios_13_0_arm64_iphoneos.whl",
        hash = "sha256:ef65e96f0fc1a7c8b7644c7011d47a8228555e7888ac4d6246f715a7f3d7c398",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/b3/7d/dac073db12f3c131598a6693253aded581e4d7d622a89864f11bfb0ca2f5/coverage-7.17.0-cp313-cp313-ios_13_0_arm64_iphonesimulator.whl",
        hash = "sha256:55939ea4c097fda2edabf80fac5e49bef15597b950a9f29fc56292a895245feb",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/00/45/877b0a9248e921080ae91d115c13192d17e308f5aee86bcc7f7bc2a54ed1/coverage-7.17.0-cp313-cp313-macosx_10_13_x86_64.whl",
        hash = "sha256:bfb6f868af552c0ceb2d19220b8cbcc2be096ca26163ac30e682a13041433429",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/4f/f5/2c48d47abec0e4590b302920334be5ee3854f96bbd22524feabb8d92b220/coverage-7.17.0-cp313-cp313-macosx_11_0_arm64.whl",
        hash = "sha256:8d823d66afd59566030539c49c7a6acaf3083996682be2dda760c63555842094",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a8/a0/ec0442f3f372c7fd742f49b3022edd392f79e37a0048e1fa333f56d01ec3/coverage-7.17.0-cp313-cp313-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:50678474e714c684b82c108e63fbb8f1bcf1266d8293a49980f1d08526f093b5",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/92/e2/eb0927ba93809f76eee69fa1e47999825fc7dbbabc3e0e1a2744f2677acb/coverage-7.17.0-cp313-cp313-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:045c1eeb19fb4eae949850a761102fffb3a5f638b97f977912f95843e54f6669",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/9a/a2/8d4c6055efb32099b15c9cc33d007b8aabebc4832f372a3274de5ba0afc5/coverage-7.17.0-cp313-cp313-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:dfb12891a773cbc2132349c77c690a045a882fe3f98b4bda50dfabb01893f9bd",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/2c/1e/93412288688a7b03f152a734c8ef086e395108a0a6a746985d3967e220f2/coverage-7.17.0-cp313-cp313-manylinux2014_ppc64le.manylinux_2_17_ppc64le.manylinux_2_28_ppc64le.whl",
        hash = "sha256:3067608b4429629f640c1b23d2f69b05d2fd45e00ebb6ee9e8fad220a6c11722",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/3c/20/7eb8d805c4f1a212245cef20181dfbf39535357985073d49730ee9cf08d4/coverage-7.17.0-cp313-cp313-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:a1762e85cbbe3b5ff9c6dcbcc1b89d5c72320094292b7b9572bf882c85e428b7",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/1a/c1/1df29630b4ed17e135c76390afcc6bd273c3dc5ba2a21a76813a600fe98c/coverage-7.17.0-cp313-cp313-musllinux_1_2_aarch64.whl",
        hash = "sha256:62bb77987d3f72a0aaa77c567ee7f9806bc2e748c8f46fafbe1fdb90dd148398",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a1/79/2365d1008d28aafe468a450a24c6c63363de794b5140223d67685cd0e205/coverage-7.17.0-cp313-cp313-musllinux_1_2_i686.whl",
        hash = "sha256:6cc31f27240d4e080437e3b8229d92f1d809c9a4f233607385373b73974e183e",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/c0/9f/f002952d295d772688dffce0d991e3822795b1e3aad158073712a5a5e86e/coverage-7.17.0-cp313-cp313-musllinux_1_2_ppc64le.whl",
        hash = "sha256:61cde5222f1933d476647c5a25ed1a8678b7703098cb5a15f4a0aa39967d8c28",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/40/fe/f9e15fbb426be97cd679ee5d359151e046f103bcd76b5092c318c26ed596/coverage-7.17.0-cp313-cp313-musllinux_1_2_riscv64.whl",
        hash = "sha256:11f5f7fb2d97a0fe865f5e7bad4eb0619b957637f676bc088d13844adf26ba95",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/c2/4a/3c398f38694387334ff4c9f71afc8e15b4fa7db7bc0bea4d5b6032eb0df0/coverage-7.17.0-cp313-cp313-musllinux_1_2_x86_64.whl",
        hash = "sha256:6e09612b1b82c9df1d2b6c85dee88d5aad3e73d77a8ec0b16ac6a7322cbdf5d9",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/bd/a9/908a3cf1a2335aec1c788682a06c2f742a62a4f987033f080de1c5fd1997/coverage-7.17.0-cp313-cp313-win32.whl",
        hash = "sha256:bd3e9eb493631ff1ca34bf5efac25b5c66724f837bf6182c4fc771c55946423d",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/13/f7/8cdd7bfd8a63b3e6b133fc395ecfc7b1cb6f561926e7e2ad050de85b83e7/coverage-7.17.0-cp313-cp313-win_amd64.whl",
        hash = "sha256:f1fc9a7cea899c51d8a53e66c2f082a3d9e461ece32418d3ef0a0b90c32bfd3d",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/09/cf/0b3fc57f735cd3831ca13d0be5312a5477d5934066683c5d34018cab7541/coverage-7.17.0-cp313-cp313-win_arm64.whl",
        hash = "sha256:e65a1e61a68493fbfbe44d8bec71b3231d81b9917f62d3dafe0e105072147e83",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/4d/e1/722462fe79912ebebc101497bd16c42413cde2dbae771017f1ec0acb84c2/coverage-7.17.0-cp314-cp314-android_24_arm64_v8a.whl",
        hash = "sha256:dc5936491e306f2f6f095bd5fba593de11eb0375cee787ca1f245c3a333a523a",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/b7/74/826b9c09f2ebfea803bccb391d935688a25309bff8e819fc446bc629c108/coverage-7.17.0-cp314-cp314-android_24_x86_64.whl",
        hash = "sha256:968c5fb6e0c83cab752d79a70209648ce4d90cae815c60fa229b59e264601062",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/6d/19/c8514d7f5e0659a96ff2bc7377119dca6d420e2761c5fc69ae37618734f8/coverage-7.17.0-cp314-cp314-ios_13_0_arm64_iphoneos.whl",
        hash = "sha256:12cb8a20ad904a5811e6660d829a586b216e5254b9b34b76dde8a4d65d827dc6",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/81/74/ef9433ce599f07d8633b4ce6e6d6921505c4ef3f7f9006f8eb66e2c278cf/coverage-7.17.0-cp314-cp314-ios_13_0_arm64_iphonesimulator.whl",
        hash = "sha256:bb5ca66937c55bc85d1a5e9c5900a3e4693a8edf2280a9b3672b7b2661a84b95",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/d8/66/26e58981940e8b3944c6a9941bec5c7f50840e7009a046712e3f3bcd9e6a/coverage-7.17.0-cp314-cp314-macosx_10_15_x86_64.whl",
        hash = "sha256:5cc15faaf318ee5040d835a62c75bc6f122d837274f3b5efd47bf9fbd4ac5b85",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/e9/63/fe175310815cc8357b83b773c9b4c20943c269f217dd825a37c4b4bfe324/coverage-7.17.0-cp314-cp314-macosx_11_0_arm64.whl",
        hash = "sha256:7d6d9d396c8b7bcaf76d774a10140b218111484e54c73a5f2a1b75655381748e",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/2c/b0/ac84761f5b4bd226696b0ec4606903d2ef7208abda0aec06c14a4218def4/coverage-7.17.0-cp314-cp314-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:42e6f170d1ac04b7eb3363310a6c41cdfd82c1fe6bf9ffbc4a86f380bdf091c7",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/e9/58/d8bdd65a661913bc12eaaa3e59742b2cb8b94f2e7f78e62184f0a58ca493/coverage-7.17.0-cp314-cp314-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:acdb5f3c96046efff9dc6c572a6acb2b8d0da09372d7b9a9ed7249cf7d17434f",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/7b/15/5d82e2f0a75ea149e0a6412e137e1d610538772fdfd7199737db7fe234da/coverage-7.17.0-cp314-cp314-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:3393209f6894713161ee82a9b0e673e58237e0f9733c6638e7a6c0c620ef0b33",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/0f/cc/e3ebfd295d1dd47c7bc84a17d73f150465a37ab388dd68fe82b495dc79a0/coverage-7.17.0-cp314-cp314-manylinux2014_ppc64le.manylinux_2_17_ppc64le.manylinux_2_28_ppc64le.whl",
        hash = "sha256:e9494d9e99389d39e6a96227749af898d8924ff591cb63944f8a98e68582bf0e",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/e0/9d/e2adff76d6544bbc6df7366d74967923c2de37ba889a006bfb875bf5857b/coverage-7.17.0-cp314-cp314-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:032d4c2db4c677eb71d43f2f8b80bf64e9346f7a3f7b6ebb13f1782f3cc6c274",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/d9/fd/ecd1e9cddf1c36b5d03c438568b1f53e63db84bb3656539d71b454484c7d/coverage-7.17.0-cp314-cp314-musllinux_1_2_aarch64.whl",
        hash = "sha256:4343a9378b964eb3cb80fa90406385de91c7e982a769ca9314d848f93bc0d3f2",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/40/b6/e17a19dccdbcad494c64691f71c1dba3e55c30625bc29ffbb88ac5a0aa8b/coverage-7.17.0-cp314-cp314-musllinux_1_2_i686.whl",
        hash = "sha256:b609df3d6d900464207532c5170a65c6ede8d2e0b91f151f90008a866395cd76",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/6a/0d/37dac534709a3fa43a937c8b0604839bb44b8670b83d143a4b78fec20d1e/coverage-7.17.0-cp314-cp314-musllinux_1_2_ppc64le.whl",
        hash = "sha256:a01ef92caeedfa4f2ad171a3a8e6fece4565de871d8bca428151bf9929f41048",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/cb/17/7c05186925b4d64a46c271dfd944e3f0c1ad89db9095c31a6df157a75df2/coverage-7.17.0-cp314-cp314-musllinux_1_2_riscv64.whl",
        hash = "sha256:a3914e2c98c34b94c26d2add3d2a61ccfd3534fc4eaa879ee290bdbb5184ba6c",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/95/65/c241cdee66a0ff86c68f6d37328e735d10e3d30cd6ff66f356039eb688d2/coverage-7.17.0-cp314-cp314-musllinux_1_2_x86_64.whl",
        hash = "sha256:e8a72b26dc5c9a9422e45472b1d67ba5caf273c524c8668cc04b23062663755e",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/db/09/e93233fe2405574ce0a31ed201c0cba3a860e085db5d2828bf12b7dc0790/coverage-7.17.0-cp314-cp314-win32.whl",
        hash = "sha256:03baf0688e14a5a44ffd1eefa8928dfc92b14565e521174e072b31b971aa1657",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/d7/77/04979eb217edb94b94afabb4bcc179f60c746f68d3fd0b12688ba9195730/coverage-7.17.0-cp314-cp314-win_amd64.whl",
        hash = "sha256:3a4459b0f389dd1e51aac3dbfc4ca35b30cae7dc99caa3c0a086d1997a985709",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a0/38/155f2f2c6769f8c43eca8a5e581443faa0908828650090b97103b4a41376/coverage-7.17.0-cp314-cp314-win_arm64.whl",
        hash = "sha256:a32ee5831b15ba239bef5d272ae586ca8acea4a661b5f2941f5a0d380e518b23",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/52/55/d6751572d9445485c4c5a51ec6ae11caa5c11b7ef2448cdccc884f7f54d9/coverage-7.17.0-cp314-cp314t-macosx_10_15_x86_64.whl",
        hash = "sha256:9c083e253e96fdeeaf48133fe836cac86ace2db215d235700e7f7532420a200c",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/2f/a8/82d37760e537bfdb9fdee285fa1e1b45bc153293d23e2331c7befedd1990/coverage-7.17.0-cp314-cp314t-macosx_11_0_arm64.whl",
        hash = "sha256:b88fb4d4d7608cbcebdc7ff7dbffc2115e3b81d6c33a79147cd79d54fcb080f4",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/24/96/70ec00a9db6d7bdd3f914eba12057360769f5cb78a98456e71fe1937deb5/coverage-7.17.0-cp314-cp314t-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:2bf3ee38a40c0570c316b9e7507c472469586906a20f289705898528c31aaea8",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/77/d8/d99be3bfbb208512f039c80b31e404138a86678fc929a17acd5b7135a6ae/coverage-7.17.0-cp314-cp314t-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:7c570293f001ea91598b90e90cb9b98fddee833e90bbede432cbd218331ccd8e",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/82/50/6cbe8b5a5060edbd21ce8109c4e900f8b7656e8b72ede6dc4d82dc0b8bfb/coverage-7.17.0-cp314-cp314t-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:791f9ee09814dd30d9562b4f4eb037a371485ec1c830b53999d2320d20c4e764",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/bd/05/d3633add01e5518dfdacfdbd1be41cb5c581412dd8bccd663edf6ef7fec8/coverage-7.17.0-cp314-cp314t-manylinux2014_ppc64le.manylinux_2_17_ppc64le.manylinux_2_28_ppc64le.whl",
        hash = "sha256:c7c5672ecf1b497de7a0b37743bef40e3b58e3207e9fe2ed6682cb0420836a88",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/57/d9/b83387780271bf9ea9f96a3aeb01c1c302c4494a927923c4fa70cd170a3f/coverage-7.17.0-cp314-cp314t-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:337f87e62e1c5f43c8198d879f677c342d152f84d3f157add12558853cbb8eaf",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/e4/be/8e80b29764ae3f4d70d44952eee3f3927eb36897490fe799e400adb7f5da/coverage-7.17.0-cp314-cp314t-musllinux_1_2_aarch64.whl",
        hash = "sha256:c8a58baa8eb6154c6645eadcc19b6c089deab78c24a612a83206f2a8a5992a7c",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/b8/c9/e702f588fe8d83ca844f133270ad0a49bf650c8cf260551ff6f11a6b6bbf/coverage-7.17.0-cp314-cp314t-musllinux_1_2_i686.whl",
        hash = "sha256:fb5745048ee20f796b0e3ab61831049e749acff188563e2af32f58ede957ac1b",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/8a/11/ee13ad14b714d75ef07c490b6e43969574a8b8b8c6d67bc741fcbacbf9c3/coverage-7.17.0-cp314-cp314t-musllinux_1_2_ppc64le.whl",
        hash = "sha256:7b5abcae74750302ac4bc77351eaee87c450e4abd3b6225eacde3858e260f8b2",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/e2/bc/854e8912c11c54aaf416e74602000589c6efbbe1f251dc90202fdabddcb6/coverage-7.17.0-cp314-cp314t-musllinux_1_2_riscv64.whl",
        hash = "sha256:4e153f0bd6509dbf837fd585f489b3328bfd98f2a718a0b15ae63032148b285c",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a8/dd/96432830ddf63bc42654de54eee77a0cd6949cc65769bda06f353323f23a/coverage-7.17.0-cp314-cp314t-musllinux_1_2_x86_64.whl",
        hash = "sha256:e42a835271922fe7bf98c7a05c78d4032f4e52bf5b07fafa1eadfdfc2f0ad22f",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ce/ee/230c6ec065a6629d41cc89323ceb54d37e2650c104f70fc108f4ee7c5051/coverage-7.17.0-cp314-cp314t-win32.whl",
        hash = "sha256:5900055351ec89fdffb34b27898815106529ded29a9496464c1ebd6313fd40fa",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/f0/1d/23eb6aadcb3c00764ff2961c0ff55f5dfa2543856d932b949bbc04fa68e9/coverage-7.17.0-cp314-cp314t-win_amd64.whl",
        hash = "sha256:5ee9c8bd13a59e301dc2aefe7aa8384633406808de051b1982775667094eb673",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/3e/f1/7df117e8e016b7a3ee459e833b3456f3610505afefd071f8727702d98439/coverage-7.17.0-cp314-cp314t-win_arm64.whl",
        hash = "sha256:0a9cb9a0fb58e6fff5442969af36094ecd6976f4907f179e33b27e15355d8f74",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/9f/a1/f9c24911755f91e6f451ca2e2c1804fbcbe9fecbc3310e341bbbbfa1d85b/coverage-7.17.0-cp315-cp315-android_24_arm64_v8a.whl",
        hash = "sha256:adabc1079ba844b096799ba8638d8df434aca1613f95bb7d5791af320cf05559",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/b0/a5/2b665b40c626e6bb40e5e8e23d91170b48b5f2f57186f46b07f2fac42386/coverage-7.17.0-cp315-cp315-android_24_x86_64.whl",
        hash = "sha256:6b4593d2871c4c801656dd5861e759f8f5156febd6b6061b02f6a72d64618b7b",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/3d/8c/22b518d61b930b8a4d62905d046c76a03675ef19b466462011dfb16439a3/coverage-7.17.0-cp315-cp315-ios_13_0_arm64_iphoneos.whl",
        hash = "sha256:c2c48a36bb970b7265b196032bfd4237c0b373f2b25ef7012d7e905b5b35c19c",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/08/5b/d3b141455944e030cd4987f055f8c84a44a1a0b28d81ae93389f44051691/coverage-7.17.0-cp315-cp315-ios_13_0_arm64_iphonesimulator.whl",
        hash = "sha256:f8bc2cd4c6aa58be1ca243fb8cddb6c3c42031fe4403991ad9cf2b3baed03d9f",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/03/24/aab2156983f7022361352640c583d08f0238e4cd7463eb921172001b4cfe/coverage-7.17.0-cp315-cp315-macosx_10_15_x86_64.whl",
        hash = "sha256:cbf0b83ce927de6053279ba61342d9f8892afde1385fcba9144cd05d4023d109",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/87/db/94697b9ccf4ec94cdad07bf94e2a21b9702247cb212d2d5f18d2b9c3d0de/coverage-7.17.0-cp315-cp315-macosx_11_0_arm64.whl",
        hash = "sha256:66efc0fb99cee34626fc17d3adac9c3cd816bfdad563bb1e983c3ef432f566d4",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a0/fd/db1c4ade4219831d590fff5aa5b7d9ceaf84586e8e60da6fff71b6182251/coverage-7.17.0-cp315-cp315-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:58a304efdf2253fb2ea03d45d0a04cc174a92a0cd5279c28c5bb893ce7410968",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/95/ee/84ed138990ed752abd73db4adffc1842d6152017d8e21809cc109a413fda/coverage-7.17.0-cp315-cp315-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:aed06129a9f530a948928260d7d2d81c47261355b0127e3c782251b38958463c",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/64/ad/c1e4367bbd1e7d562d6bc979c82b542f2040544e95a8cd995b694caf0e1a/coverage-7.17.0-cp315-cp315-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:f6cdb47a9be2d3313829bed1d296086287682a3ee901ff987b3432b45705b771",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/b5/3a/e8e8509b0940403eab15d86f70022790a01fce3e971a161919c544953f7a/coverage-7.17.0-cp315-cp315-manylinux2014_ppc64le.manylinux_2_17_ppc64le.manylinux_2_28_ppc64le.whl",
        hash = "sha256:804fbaf81d09b34e2f8b1159d01e211a50713d743d32fd9b2ca6cf0ae507a66f",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/1f/77/d64bbdbb734b1059ebcde2b5df567f142a9948079e51af9b0abf8c9ec17b/coverage-7.17.0-cp315-cp315-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:b2afebb96da9a1bbca142f8cc12320c14e5c215e0a49cded4f191f5a31506a28",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/e2/29/7cf81f08a254532c074eb52cfe6b12bb753d08f2997269c9fac8de359541/coverage-7.17.0-cp315-cp315-musllinux_1_2_aarch64.whl",
        hash = "sha256:bd04fd23206be9ad3de13b0b39313094fafa66a1f6baf70f5471c004a9fac47d",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/7f/56/bacea6dee2d5ccb31ab0cfffcee87ca7efa80ff048840209c8013aeaf02e/coverage-7.17.0-cp315-cp315-musllinux_1_2_i686.whl",
        hash = "sha256:5ebfbc87836529a31d25c2dec1262c38eea852ec1c46c0f690a515a7339d9c5b",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a4/97/fd8a6a63740f9ee177c53b59e2f4d0752369bb0fd154086a1e69aa1fb255/coverage-7.17.0-cp315-cp315-musllinux_1_2_ppc64le.whl",
        hash = "sha256:a59c3b470ac3b2432af3598a996affbeb10236cd899a005c1c4e517fcff8b592",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/c1/37/7cd3d3520d45db3788456452b65446182c08f2a7c276f40c9dd11966be02/coverage-7.17.0-cp315-cp315-musllinux_1_2_riscv64.whl",
        hash = "sha256:7fef12cec4b96f59e09761cbd4fc9bdf4788062d1ae435b920241fc16c8a9549",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/c1/b9/80343a55e07d854927a915cc21a52e350ae1db9ead33f0248507b960785f/coverage-7.17.0-cp315-cp315-musllinux_1_2_x86_64.whl",
        hash = "sha256:a14e8d69464da9cbe1dc29e7116dbd37296d1d51a695327c478e250349085089",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/f3/32/e4c816f0cb3efdc6392bb276ff88359729f9dec605bdd3c1c7a44776f759/coverage-7.17.0-cp315-cp315-win32.whl",
        hash = "sha256:9a66074231799d8884d267234d49f60c90b43a945dfe069646b72f3058cd4e67",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/43/14/283120142ac281834808584249b89957de997c28573ddd65ae106b622121/coverage-7.17.0-cp315-cp315-win_amd64.whl",
        hash = "sha256:79cf71e5f9a48877ccfed5baa2c72f45af4feeaa596249e23eb15b473134830e",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/b9/bc/83dbc6c3bd58042afaefcb0cfd7d7a2e3076989a2f3d9bc6e6edac819784/coverage-7.17.0-cp315-cp315-win_arm64.whl",
        hash = "sha256:09e563b49c81cd0a33734e926d7a4a6ef1778d74304cde2dcc3aff8b30ea1036",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/00/ed/9463d1cb1766a2570343a372c2871c7fb4d561e5051f029399f4d57ce947/coverage-7.17.0-cp315-cp315t-macosx_10_15_x86_64.whl",
        hash = "sha256:a5e2e0625dfc789af0b2e10acfc106b352f314fffbd19e6392a7961c8cbe5d9a",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/ae/59/6536c7fa87be13236b4184fc395f14d18f622a5b8ef7448a6bfdf5f24ec0/coverage-7.17.0-cp315-cp315t-macosx_11_0_arm64.whl",
        hash = "sha256:194562ab1eff0d85aee8a17ce4c5c0bc1ebf70a629a7145257123156ad100fd6",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/b0/bc/4ffae6038f78382c9ab6a4969cb5fc01d50b083d119851085807629abe88/coverage-7.17.0-cp315-cp315t-manylinux1_i686.manylinux_2_28_i686.manylinux_2_5_i686.whl",
        hash = "sha256:85682ca89bc4601125dcdff23fa70e6274e13c9ad502fba845e6c274ab2c6569",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/c0/60/cae4b708b4217d33ebf66b9c57f8910a257346b3eaf054a78d73605ddc4c/coverage-7.17.0-cp315-cp315t-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl",
        hash = "sha256:0d0fac604a962ff546beb038cba9a5a09d88e6e3f01612fb46f7bd4fe5dc8dca",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/a9/84/1225ab04e55a6a2e483e903a5eb0f8f081cb5325df833594534aa288d91c/coverage-7.17.0-cp315-cp315t-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl",
        hash = "sha256:72edd4f9483ae30cd1ba4f230687840ef7b58a16afb1c9e81131fd6d64655f36",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/94/ad/567f8dd9246a553aa8753732c41f0e0654e98e9a617d6282e64eae0e6aa8/coverage-7.17.0-cp315-cp315t-manylinux2014_ppc64le.manylinux_2_17_ppc64le.manylinux_2_28_ppc64le.whl",
        hash = "sha256:91e487ad07c511da77b574820141a7c2da09bc2a4b4090b5be2424295d100697",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/66/5f/e0ee76895df40601e4aedffb6b8e71ea48e276a629fb4488b92cffffca14/coverage-7.17.0-cp315-cp315t-manylinux_2_31_riscv64.manylinux_2_39_riscv64.whl",
        hash = "sha256:1cabb31531002fef5197de5df3c84730aef01e750e25154b9813a2583435aba2",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/19/6d/d19c6e45e940e5b9ba697b7be9a8e63cef73d90bdea45b670a59df466717/coverage-7.17.0-cp315-cp315t-musllinux_1_2_aarch64.whl",
        hash = "sha256:c9ac886242bbd50fb35a2242ba79555a99891e657da33f98b7ca968e3488a350",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/27/a3/b2731bb7aef2db800b330603675c3fa58a6497a05d5b5f8625f3b6285f68/coverage-7.17.0-cp315-cp315t-musllinux_1_2_i686.whl",
        hash = "sha256:d45cdc495671fc99268ff3653e0da4244972e9fc0e1fc3ea9de18781ad28963a",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/50/75/d0c90a81b6b6607933109914dc8b0ef0a5f4cacf9482ca868ae773ee5d0b/coverage-7.17.0-cp315-cp315t-musllinux_1_2_ppc64le.whl",
        hash = "sha256:12961f738d717a046d4bf3f8d1727eb3ebe2ed5478ff96cd6233d4dfc39323d3",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/64/1e/f038f3a2614e9ef839a40a184713aca40b8ed79e626ab5cdc388771045df/coverage-7.17.0-cp315-cp315t-musllinux_1_2_riscv64.whl",
        hash = "sha256:1ee0a982b0e1230b3edf768a7dd022bd2377303763895327ac62deb5efacee03",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/c9/30/8d636e639b2d8b1934128573402a7caf66c8cfbc794fa02061d84f115c34/coverage-7.17.0-cp315-cp315t-musllinux_1_2_x86_64.whl",
        hash = "sha256:460679f53893081edb94eeed011d26be37228ba649b853fd2aed7e4394fb1f35",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/73/7a/219f6b391cb0636242d06c390a8add5af91afa3e92afd0380dbedd34f487/coverage-7.17.0-cp315-cp315t-win32.whl",
        hash = "sha256:600e121e412cd6bdb52ec105b95c6a04da0c9710d1534f6e64a42db667907802",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/f0/3f/514d294319c5eac11494394545de209079f33993e14526c220eab29b2a96/coverage-7.17.0-cp315-cp315t-win_amd64.whl",
        hash = "sha256:c3e11b81faafb1f063248735c3e2c5c4183fc1db2c7f46782170dd7760dffcbc",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/f6/82/c0d8bb0a67df838fc7bc6f4060ffc404fd1154fd18e624d83e6abc41aeef/coverage-7.17.0-cp315-cp315t-win_arm64.whl",
        hash = "sha256:d472ee1c64868a917a47f02ffb4ac8c22b477f7589d57a3eb0c58b1ad4f0137c",
        marker = "python_full_version >= '3.15'",
    ),
    struct(
        url = "https://files.pythonhosted.org/packages/c9/17/48032919343afa2906112d458aceda2043afdb24a2ee8eb4c60904d8ddf1/coverage-7.17.0-py3-none-any.whl",
        hash = "sha256:bac487dce0d2aff28ddf1a533a916f771416eee0e493960f611e49037b878e9d",
        marker = "python_full_version >= '3.15'",
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

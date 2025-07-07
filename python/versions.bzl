# Copyright 2022 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""The Python versions we use for the toolchains.
"""

load("//python/private:platform_info.bzl", "platform_info")

# Values present in the @platforms//os package
MACOS_NAME = "osx"
LINUX_NAME = "linux"
WINDOWS_NAME = "windows"

FREETHREADED = "-freethreaded"
MUSL = "-musl"
INSTALL_ONLY = "install_only"

DEFAULT_RELEASE_BASE_URL = "https://github.com/astral-sh/python-build-standalone/releases/download"

# When updating the versions and releases, run the following command to get
# the hashes:
#   bazel run //python/private:print_toolchains_checksums --//python/config_settings:python_version={major}.{minor}.{patch}
#
# To print hashes for all of the specified versions, run:
#   bazel run //python/private:print_toolchains_checksums --//python/config_settings:python_version=""
#
# Note, to users looking at how to specify their tool versions, coverage_tool version for each
# interpreter can be specified by:
#   "3.8.10": {
#       "url": "20210506/cpython-{python_version}-{platform}-pgo+lto-20210506T0943.tar.zst",
#       "sha256": {
#           "x86_64-apple-darwin": "8d06bec08db8cdd0f64f4f05ee892cf2fcbc58cfb1dd69da2caab78fac420238",
#           "x86_64-unknown-linux-gnu": "aec8c4c53373b90be7e2131093caa26063be6d9d826f599c935c0e1042af3355",
#       },
#       "coverage_tool": {
#           "x86_64-apple-darwin": "<label_for_darwin>"",
#           "x86_64-unknown-linux-gnu": "<label_for_linux>"",
#       },
#       "strip_prefix": "python",
#   },
#
# It is possible to provide lists in "url". It is also possible to provide patches or patch_strip.
#
# buildifier: disable=unsorted-dict-items
TOOL_VERSIONS = {
    "3.8.20": {
        "url": "20241002/cpython-{python_version}+20241002-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "2ddfc04bdb3e240f30fb782fa1deec6323799d0e857e0b63fa299218658fd3d4",
            "aarch64-unknown-linux-gnu": "9d8798f9e79e0fc0f36fcb95bfa28a1023407d51a8ea5944b4da711f1f75f1ed",
            "x86_64-apple-darwin": "68d060cd373255d2ca5b8b3441363d5aa7cc45b0c11bbccf52b1717c2b5aa8bb",
            "x86_64-pc-windows-msvc": "41b6709fec9c56419b7de1940d1f87fa62045aff81734480672dcb807eedc47e",
            "x86_64-unknown-linux-gnu": "285e141c36f88b2e9357654c5f77d1f8fb29cc25132698fe35bb30d787f38e87",
        },
        "strip_prefix": "python",
    },
    "3.9.10": {
        "url": "20220227/cpython-{python_version}+20220227-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "ad66c2a3e7263147e046a32694de7b897a46fb0124409d29d3a93ede631c8aee",
            "aarch64-unknown-linux-gnu": "12dd1f125762f47975990ec744532a1cf3db74ad60f4dfb476ca42deb7f78ca4",
            "x86_64-apple-darwin": "fdaf594142446029e314a9beb91f1ac75af866320b50b8b968181e592550cd68",
            "x86_64-pc-windows-msvc": "c145d9d8143ce163670af124b623d7a2405143a3708b033b4d33eed355e61b24",
            "x86_64-unknown-linux-gnu": "455089cc576bd9a58db45e919d1fc867ecdbb0208067dffc845cc9bbf0701b70",
        },
        "strip_prefix": "python",
    },
    "3.9.12": {
        "url": "20220502/cpython-{python_version}+20220502-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "8dee06c07cc6429df34b6abe091a4684a86f7cec76f5d1ccc1c3ce2bd11168df",
            "aarch64-unknown-linux-gnu": "2ee1426c181e65133e57dc55c6a685cb1fb5e63ef02d684b8a667d5c031c4203",
            "x86_64-apple-darwin": "2453ba7f76b3df3310353b48c881d6cff622ba06e30d2b6ae91588b2bc9e481a",
            "x86_64-pc-windows-msvc": "3024147fd987d9e1b064a3d94932178ff8e0fe98cfea955704213c0762fee8df",
            "x86_64-unknown-linux-gnu": "ccca12f698b3b810d79c52f007078f520d588232a36bc12ede944ec3ea417816",
        },
        "strip_prefix": "python",
    },
    "3.9.13": {
        "url": "20220802/cpython-{python_version}+20220802-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "d9603edc296a2dcbc59d7ada780fd12527f05c3e0b99f7545112daf11636d6e5",
            "aarch64-unknown-linux-gnu": "80415aac1b96255b9211f6a4c300f31e9940c7e07a23d0dec12b53aa52c0d25e",
            "x86_64-apple-darwin": "9540a7efb7c8a54a48aff1cb9480e49588d9c0a3f934ad53f5b167338174afa3",
            "x86_64-pc-windows-msvc": "b538127025a467c64b3351babca2e4d2ea7bdfb7867d5febb3529c34456cdcd4",
            "x86_64-unknown-linux-gnu": "ce1cfca2715e7e646dd618a8cb9baff93000e345ccc979b801fc6ccde7ce97df",
        },
        "strip_prefix": "python",
    },
    "3.9.15": {
        "url": "20221106/cpython-{python_version}+20221106-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "64dc7e1013481c9864152c3dd806c41144c79d5e9cd3140e185c6a5060bdc9ab",
            "aarch64-unknown-linux-gnu": "52a8c0a67fb919f80962d992da1bddb511cdf92faf382701ce7673e10a8ff98f",
            "x86_64-apple-darwin": "f2bcade6fc976c472f18f2b3204d67202d43ae55cf6f9e670f95e488f780da08",
            "x86_64-pc-windows-msvc": "022daacab215679b87f0d200d08b9068a721605fa4721ebeda38220fc641ccf6",
            "x86_64-unknown-linux-gnu": "cdc3a4cfddcd63b6cebdd75b14970e02d8ef0ac5be4d350e57ab5df56c19e85e",
        },
        "strip_prefix": "python",
    },
    "3.9.16": {
        "url": "20230507/cpython-{python_version}+20230507-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "c1de1d854717a6245f45262ef1bb17b09e2c587590e7e3f406593c143ff875bd",
            "aarch64-unknown-linux-gnu": "f629b75ebfcafe9ceee2e796b7e4df5cf8dbd14f3c021afca078d159ab797acf",
            "ppc64le-unknown-linux-gnu": "ff3ac35c58f67839aff9b5185a976abd3d1abbe61af02089f7105e876c1fe284",
            "x86_64-apple-darwin": "3abc4d5fbbc80f5f848f280927ac5d13de8dc03aabb6ae65d8247cbb68e6f6bf",
            "x86_64-pc-windows-msvc": "cdabb47204e96ce7ea31fbd0b5ed586114dd7d8f8eddf60a509a7f70b48a1c5e",
            "x86_64-unknown-linux-gnu": "2b6e146234a4ef2a8946081fc3fbfffe0765b80b690425a49ebe40b47c33445b",
        },
        "strip_prefix": "python",
    },
    "3.9.17": {
        "url": "20230726/cpython-{python_version}+20230726-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "73dbe2d702210b566221da9265acc274ba15275c5d0d1fa327f44ad86cde9aa1",
            "aarch64-unknown-linux-gnu": "b77012ddaf7e0673e4aa4b1c5085275a06eee2d66f33442b5c54a12b62b96cbe",
            "ppc64le-unknown-linux-gnu": "c591a28d943dce5cf9833e916125fdfbeb3120270c4866ee214493ccb5b83c3c",
            "s390x-unknown-linux-gnu": "01454d7cc7c9c2fccde42ba868c4f372eaaafa48049d49dd94c9cf2875f497e6",
            "x86_64-apple-darwin": "dfe1bea92c94b9cb779288b0b06e39157c5ff7e465cdd24032ac147c2af485c0",
            "x86_64-pc-windows-msvc": "9b9a1e21eff29dcf043cea38180cf8ca3604b90117d00062a7b31605d4157714",
            "x86_64-unknown-linux-gnu": "26c4a712b4b8e11ed5c027db5654eb12927c02da4857b777afb98f7a930ce637",
        },
        "strip_prefix": "python",
    },
    "3.9.18": {
        "url": "20240224/cpython-{python_version}+20240224-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "2548f911a6e316575c303ba42bb51540dc9b47a9f76a06a2a37460d93b177aa2",
            "aarch64-unknown-linux-gnu": "e5bc5196baa603d635ee6b0cd141e359752ad3e8ea76127eb9141a3155c51200",
            "ppc64le-unknown-linux-gnu": "d6b18df7a25fe034fd5ce4e64216df2cc78b2d4d908d2a1c94058ae700d73d22",
            "s390x-unknown-linux-gnu": "15d059507c7e900e9665f31e8d903e5a24a68ceed24f9a1c5ac06ab42a354f3f",
            "x86_64-apple-darwin": "171d8b472fce0295be0e28bb702c43d5a2a39feccb3e72efe620ac3843c3e402",
            "x86_64-pc-windows-msvc": "a9bdbd728ed4c353a4157ecf74386117fb2a2769a9353f491c528371cfe7f6cd",
            "x86_64-unknown-linux-gnu": "0e5663025121186bd17d331538a44f48b41baff247891d014f3f962cbe2716b4",
        },
        "strip_prefix": "python",
    },
    "3.9.19": {
        "url": "20240726/cpython-{python_version}+20240726-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "0e5a7aae57c53d7a849bc7f67764a947b626e3fe8d4d41a8eed11d9e4be0b1c6",
            "aarch64-unknown-linux-gnu": "05ec896db9a9d4fe8004b4e4b6a6fdc588a015fedbddb475490885b0d9c7d9b3",
            "ppc64le-unknown-linux-gnu": "bfff0e3d536b2f0c315e85926cc317b7b756701b6de781a8972cefbdbc991ca2",
            "s390x-unknown-linux-gnu": "059ec97080b205ea5f1ddf71c18e22b691e8d68192bd37d13ad8f4359915299d",
            "x86_64-apple-darwin": "f2ae9fcac044a329739b8c1676245e8cb6b3094416220e71823d2673bdea0bdb",
            "x86_64-pc-windows-msvc": "a8df6a00140055c9accb0be632e7add951d587bbe3d63c40827bbd5145d8f557",
            "x86_64-unknown-linux-gnu": "cbf94cb1c9d4b5501d9b3652f6e8400c2cab7c41dfea48d344d9e7f29692b91b",
        },
        "strip_prefix": "python",
    },
    "3.9.20": {
        "url": "20241016/cpython-{python_version}+20241016-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "34ab2bc4c51502145e1a624b4e4ea06877e3d1934a88cc73ac2e0fd5fd439b75",
            "aarch64-unknown-linux-gnu": "1e486c054a4e86666cf24e04f5e29456324ba9c2b95bf1cae1805be90d3da154",
            "ppc64le-unknown-linux-gnu": "9a24ccdbfc7f67545d859128f02a3150a160ea6c2fc134b0773bf56f2d90b397",
            "s390x-unknown-linux-gnu": "2cee381069bf344fb20eba609af92dfe7ba67eb75bea08eeccf11048a2c380c0",
            "x86_64-apple-darwin": "193dc7f0284e4917d52b17a077924474882ee172872f2257cfe3375d6d468ed9",
            "x86_64-pc-windows-msvc": "5069008a237b90f6f7a86956903f2a0221b90d471daa6e4a94831eaa399e3993",
            "x86_64-unknown-linux-gnu": "c20ee831f7f46c58fa57919b75a40eb2b6a31e03fd29aaa4e8dab4b9c4b60d5d",
            "x86_64-unknown-linux-musl": "5c1cc348e317fe7af1acd6a7f665b46eccb554b20d6533f0e76c53f44d4556cc",
        },
        "strip_prefix": "python",
    },
    "3.9.21": {
        "url": "20250317/cpython-{python_version}+20250317-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "2a7d83db10c082ce59e9c4b8bd6c5790310198fb759a7c94aceebac1d93676d3",
            "aarch64-unknown-linux-gnu": "758ebbc4d60b3ca26cf21720232043ad626373fbeb6632122e5db622a1f55465",
            "ppc64le-unknown-linux-gnu": "3c7c0cc16468659049ac2f843ffba29144dd987869c943b83c2730569b7f57bd",
            "riscv64-unknown-linux-gnu": "ef1463ad5349419309060854a5f942b0bd7bd0b9245b53980129836187e68ad9",
            "s390x-unknown-linux-gnu": "e66e52dcbe3e20153e7d5844451bf58a69f41b858348e0f59c547444bfe191ee",
            "x86_64-apple-darwin": "786ebd91e4dd0920acf60aa3428a627a937342d2455f7eb5e9a491517c32db3d",
            "x86_64-pc-windows-msvc": "5392cee2ef7cd20b34128384d0b31864fb3c02bdb7a8ae6995cfec621bb657bc",
            "x86_64-unknown-linux-gnu": "6f426b5494e90701ffa2753e229252e8b3ac61151a09c8cd6c0a649512df8ab2",
            "x86_64-unknown-linux-musl": "6113c6c5f88d295bb26279b8a49d74126ee12db137854e0d8c3077051a4eddc4",
        },
        "strip_prefix": "python",
    },
    "3.9.23": {
        "url": "20250702/cpython-{python_version}+20250702-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "f9ce2f9f99a84108d3fde97c37b0cada6379b3f9d1d5ef1c8e940b9eaa811c18",
            "aarch64-unknown-linux-gnu": "aa830b41391a2b57640636e9c172df8cf560777e0611fd098b2b5471c541a51e",
            "ppc64le-unknown-linux-gnu": "97132753da44781c3a2fcd24503197844f4cce4ea0dd20290675f4020df377a0",
            "riscv64-unknown-linux-gnu": "a6560df42a9afe6605cc578572b20cbf798c7fdf7381ef2dda0d3715124408d0",
            "s390x-unknown-linux-gnu": "936e5e940a13c0189d29e4755ec20f10a70ba378dc9e739dc114d730a91a2ee5",
            "x86_64-apple-darwin": "a82445abf3797bb699ce9f7371e3a6357ab3ec8fc6d25f36a88291b2cd495980",
            "x86_64-pc-windows-msvc": "eb32d4fdd3c929ad9601f3fe9f944b038db430003bc5d5623db068da4edf7628",
            "x86_64-unknown-linux-gnu": "c9bb5cb35f2c9fb05fbe9aec84d555f6d3c0773e07d42e74f92a27e866e15657",
            "x86_64-unknown-linux-musl": "7d1dbd48c8e558555c4aad0d367831ca257edd625688d1d902d6f72f02c224f9",
        },
        "strip_prefix": "python",
    },
    "3.10.2": {
        "url": "20220227/cpython-{python_version}+20220227-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "1409acd9a506e2d1d3b65c1488db4e40d8f19d09a7df099667c87a506f71c0ef",
            "aarch64-unknown-linux-gnu": "8f351a8cc348bb45c0f95b8634c8345ec6e749e483384188ad865b7428342703",
            "x86_64-apple-darwin": "8146ad4390710ec69b316a5649912df0247d35f4a42e2aa9615bffd87b3e235a",
            "x86_64-pc-windows-msvc": "a1d9a594cd3103baa24937ad9150c1a389544b4350e859200b3e5c036ac352bd",
            "x86_64-unknown-linux-gnu": "9b64eca2a94f7aff9409ad70bdaa7fbbf8148692662e764401883957943620dd",
        },
        "strip_prefix": "python",
    },
    "3.10.4": {
        "url": "20220502/cpython-{python_version}+20220502-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "2c99983d1e83e4b6e7411ed9334019f193fba626344a50c36fba6c25d4de78a2",
            "aarch64-unknown-linux-gnu": "d8098c0c54546637e7516f93b13403b11f9db285def8d7abd825c31407a13d7e",
            "x86_64-apple-darwin": "f2711eaffff3477826a401d09a013c6802f11c04c63ab3686aa72664f1216a05",
            "x86_64-pc-windows-msvc": "bee24a3a5c83325215521d261d73a5207ab7060ef3481f76f69b4366744eb81d",
            "x86_64-unknown-linux-gnu": "f6f871e53a7b1469c13f9bd7920ad98c4589e549acad8e5a1e14760fff3dd5c9",
        },
        "strip_prefix": "python",
    },
    "3.10.6": {
        "url": "20220802/cpython-{python_version}+20220802-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "efaf66acdb9a4eb33d57702607d2e667b1a319d58c167a43c96896b97419b8b7",
            "aarch64-unknown-linux-gnu": "81625f5c97f61e2e3d7e9f62c484b1aa5311f21bd6545451714b949a29da5435",
            "x86_64-apple-darwin": "7718411adf3ea1480f3f018a643eb0550282aefe39e5ecb3f363a4a566a9398c",
            "x86_64-pc-windows-msvc": "91889a7dbdceea585ff4d3b7856a6bb8f8a4eca83a0ff52a73542c2e67220eaa",
            "x86_64-unknown-linux-gnu": "55aa2190d28dcfdf414d96dc5dcea9fe048fadcd583dc3981fec020869826111",
        },
        "strip_prefix": "python",
    },
    "3.10.8": {
        "url": "20221106/cpython-{python_version}+20221106-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "d52b03817bd245d28e0a8b2f715716cd0fcd112820ccff745636932c76afa20a",
            "aarch64-unknown-linux-gnu": "33170bef18c811906b738be530f934640491b065bf16c4d276c6515321918132",
            "x86_64-apple-darwin": "525b79c7ce5de90ab66bd07b0ac1008bafa147ddc8a41bef15ffb7c9c1e9e7c5",
            "x86_64-pc-windows-msvc": "f2b6d2f77118f06dd2ca04dae1175e44aaa5077a5ed8ddc63333c15347182bfe",
            "x86_64-unknown-linux-gnu": "6c8db44ae0e18e320320bbaaafd2d69cde8bfea171ae2d651b7993d1396260b7",
        },
        "strip_prefix": "python",
    },
    "3.10.9": {
        "url": "20230116/cpython-{python_version}+20230116-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "018d05a779b2de7a476f3b3ff2d10f503d69d14efcedd0774e6dab8c22ef84ff",
            "aarch64-unknown-linux-gnu": "2003750f40cd09d4bf7a850342613992f8d9454f03b3c067989911fb37e7a4d1",
            "x86_64-apple-darwin": "0e685f98dce0e5bc8da93c7081f4e6c10219792e223e4b5886730fd73a7ba4c6",
            "x86_64-pc-windows-msvc": "59c6970cecb357dc1d8554bd0540eb81ee7f6d16a07acf3d14ed294ece02c035",
            "x86_64-unknown-linux-gnu": "d196347aeb701a53fe2bb2b095abec38d27d0fa0443f8a1c2023a1bed6e18cdf",
        },
        "strip_prefix": "python",
    },
    "3.10.11": {
        "url": "20230507/cpython-{python_version}+20230507-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "8348bc3c2311f94ec63751fb71bd0108174be1c4def002773cf519ee1506f96f",
            "aarch64-unknown-linux-gnu": "c7573fdb00239f86b22ea0e8e926ca881d24fde5e5890851339911d76110bc35",
            "ppc64le-unknown-linux-gnu": "73a9d4c89ed51be39dd2de4e235078281087283e9fdedef65bec02f503e906ee",
            "x86_64-apple-darwin": "bd3fc6e4da6f4033ebf19d66704e73b0804c22641ddae10bbe347c48f82374ad",
            "x86_64-pc-windows-msvc": "9c2d3604a06fcd422289df73015cd00e7271d90de28d2c910f0e2309a7f73a68",
            "x86_64-unknown-linux-gnu": "c5bcaac91bc80bfc29cf510669ecad12d506035ecb3ad85ef213416d54aecd79",
        },
        "strip_prefix": "python",
    },
    "3.10.12": {
        "url": "20230726/cpython-{python_version}+20230726-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "bc66c706ea8c5fc891635fda8f9da971a1a901d41342f6798c20ad0b2a25d1d6",
            "aarch64-unknown-linux-gnu": "fee80e221663eca5174bd794cb5047e40d3910dbeadcdf1f09d405a4c1c15fe4",
            "ppc64le-unknown-linux-gnu": "bb5e8cb0d2e44241725fa9b342238245503e7849917660006b0246a9c97b1d6c",
            "s390x-unknown-linux-gnu": "8d33d435ae6fb93ded7fc26798cc0a1a4f546a4e527012a1e2909cc314b332df",
            "x86_64-apple-darwin": "8a6e3ed973a671de468d9c691ed9cb2c3a4858c5defffcf0b08969fba9c1dd04",
            "x86_64-pc-windows-msvc": "c1a31c353ca44de7d1b1a3b6c55a823e9c1eed0423d4f9f66e617bdb1b608685",
            "x86_64-unknown-linux-gnu": "a476dbca9184df9fc69fe6309cda5ebaf031d27ca9e529852437c94ec1bc43d3",
        },
        "strip_prefix": "python",
    },
    "3.10.13": {
        "url": "20240224/cpython-{python_version}+20240224-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "5fdc0f6a5b5a90fd3c528e8b1da8e3aac931ea8690126c2fdb4254c84a3ff04a",
            "aarch64-unknown-linux-gnu": "a898a88705611b372297bb8fe4d23cc16b8603ce5f24494c3a8cfa65d83787f9",
            "ppc64le-unknown-linux-gnu": "c23706e138a0351fc1e9def2974af7b8206bac7ecbbb98a78f5aa9e7535fee42",
            "s390x-unknown-linux-gnu": "09be8fb2cdfbb4a93d555f268f244dbe4d8ff1854b2658e8043aa4ec08aede3e",
            "x86_64-apple-darwin": "6378dfd22f58bb553ddb02be28304d739cd730c1f95c15c74955c923a1bc3d6a",
            "x86_64-pc-windows-msvc": "086f7fe9156b897bb401273db8359017104168ac36f60f3af4e31ac7acd6634e",
            "x86_64-unknown-linux-gnu": "d995d032ca702afd2fc3a689c1f84a6c64972ecd82bba76a61d525f08eb0e195",
        },
        "strip_prefix": "python",
    },
    "3.10.14": {
        "url": "20240726/cpython-{python_version}+20240726-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "164d89f0df2feb689981864ecc1dffb19e6aa3696c8880166de555494fe92607",
            "aarch64-unknown-linux-gnu": "39bcd46b4d70e40da177c55259be16d5c2be7a3f7f93f1e3bde47e71b4833f29",
            "ppc64le-unknown-linux-gnu": "549d38b9ef59cba9ab2990025255231bfa1cb32b4bc5eac321667640fdee19d1",
            "s390x-unknown-linux-gnu": "de4bc878a8666c734f983db971610980870148f333bda8b0c34abfaeae88d7ec",
            "x86_64-apple-darwin": "1a1455838cd1e8ed0da14a152a2d559a2fd3a6047ba7013e841db4a35a228c1d",
            "x86_64-pc-windows-msvc": "7f68821a8b5445267eca480660364ebd06ec84632b336770c6e39de07ac0f6c3",
            "x86_64-unknown-linux-gnu": "32b34cd13d9d745b3db3f3b8398ab2c07de74544829915dbebd8dce39bdc405e",
        },
        "strip_prefix": "python",
    },
    "3.10.15": {
        "url": "20241016/cpython-{python_version}+20241016-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "f64776f455a44c24d50f947c813738cfb7b9ac43732c44891bc831fa7940a33c",
            "aarch64-unknown-linux-gnu": "eb58581f85fde83d1f3e8e1f8c6f5a15c7ae4fdbe3b1d1083931f9167fdd8dbc",
            "ppc64le-unknown-linux-gnu": "0c45af4e7525e2db59901606db32b2896ac1e9830c6f95551402207f537c2ce4",
            "s390x-unknown-linux-gnu": "de205896b070e6f5259ac0f2b3379eead875ea84e6a6ef533b89886fcbb46a4c",
            "x86_64-apple-darwin": "90b46dfb1abd98d45663c7a2a8c45d3047a59391d8586d71b459cec7b75f662b",
            "x86_64-pc-windows-msvc": "e48952619796c66ec9719867b87be97edca791c2ef7fbf87d42c417c3331609e",
            "x86_64-unknown-linux-gnu": "3db2171e03c1a7acdc599fba583c1b92306d3788b375c9323077367af1e9d9de",
            "x86_64-unknown-linux-musl": "ed519c47d9620eb916a6f95ec2875396e7b1a9ab993ee40b2f31b837733f318c",
        },
        "strip_prefix": "python",
    },
    "3.10.16": {
        "url": "20250317/cpython-{python_version}+20250317-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "e99f8457d9c79592c036489c5cfa78df76e4762d170665e499833e045d82608f",
            "aarch64-unknown-linux-gnu": "76d0f04d2444e77200fdc70d1c57480e29cca78cb7420d713bc1c523709c198d",
            "ppc64le-unknown-linux-gnu": "39c9b3486de984fe1d72d90278229c70d6b08bcf69cd55796881b2d75077b603",
            "riscv64-unknown-linux-gnu": "ebe949ada9293581c17d9bcdaa8f645f67d95f73eac65def760a71ef9dd6600d",
            "s390x-unknown-linux-gnu": "9b2fc0b7f1c75b48e799b6fa14f7e24f5c61f2db82e3c65d13ed25e08f7f0857",
            "x86_64-apple-darwin": "e03e62dbe95afa2f56b7344ff3bd061b180a0b690ff77f9a1d7e6601935e05ca",
            "x86_64-pc-windows-msvc": "c7e0eb0ff5b36758b7a8cacd42eb223c056b9c4d36eded9bf5b9fe0c0b9aeb08",
            "x86_64-unknown-linux-gnu": "b350c7e63956ca8edb856b91316328e0fd003a840cbd63d08253af43b2c63643",
            "x86_64-unknown-linux-musl": "6ed64923ee4fbea4c5780f1a5a66651d239191ac10bd23420db4f5e4e0bf79c4",
        },
        "strip_prefix": "python",
    },
    "3.10.18": {
        "url": "20250702/cpython-{python_version}+20250702-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "8f9e5395e3571fbb891a0be6428b4516fbde4064799ce6bda4a3c8f4e7860bd4",
            "aarch64-unknown-linux-gnu": "b2d09fab0e4340621edb30c769be8b29dddc2776dad820298592eb6aa1970ec1",
            "ppc64le-unknown-linux-gnu": "eafbbb7edafbda87e2080e5677855373f8b21606050229733a7352822ee4d84e",
            "riscv64-unknown-linux-gnu": "113eb95dbfe8a24756239007239e18ae59c7fc54e6af46f8353f290225a3f811",
            "s390x-unknown-linux-gnu": "fcbfa04bc9f9da1af4751fa916e224956c410ee23033b4fddeca9d2c64830362",
            "x86_64-apple-darwin": "9a890f21ecc9692cffec77901fd7a786a330dd461fa97ecb10359ee21ca2be79",
            "x86_64-pc-windows-msvc": "59399253bb9f864da6858c0e0e940250ebfdfd2609796dadc201aa487633fe84",
            "x86_64-unknown-linux-gnu": "4be698bff9f4197fdbb5a82c03d57f4ec5972960492ad045c82ca53a9480342a",
            "x86_64-unknown-linux-musl": "20b0fcae6ece29c681b5fd8e1b740000b6f8b907e68ba5621d029dfaa234b23b",
        },
        "strip_prefix": "python",
    },
    "3.11.1": {
        "url": "20230116/cpython-{python_version}+20230116-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "4918cdf1cab742a90f85318f88b8122aeaa2d04705803c7b6e78e81a3dd40f80",
            "aarch64-unknown-linux-gnu": "debf15783bdcb5530504f533d33fda75a7b905cec5361ae8f33da5ba6599f8b4",
            "x86_64-apple-darwin": "20a4203d069dc9b710f70b09e7da2ce6f473d6b1110f9535fb6f4c469ed54733",
            "x86_64-pc-windows-msvc": "edc08979cb0666a597466176511529c049a6f0bba8adf70df441708f766de5bf",
            "x86_64-unknown-linux-gnu": "02a551fefab3750effd0e156c25446547c238688a32fabde2995c941c03a6423",
        },
        "strip_prefix": "python",
    },
    "3.11.3": {
        "url": "20230507/cpython-{python_version}+20230507-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "09e412506a8d63edbb6901742b54da9aa7faf120b8dbdce56c57b303fc892c86",
            "aarch64-unknown-linux-gnu": "8190accbbbbcf7620f1ff6d668e4dd090c639665d11188ce864b62554d40e5ab",
            "ppc64le-unknown-linux-gnu": "767d24f3570b35fedb945f5ac66224c8983f2d556ab83c5cfaa5f3666e9c212c",
            "x86_64-apple-darwin": "f710b8d60621308149c100d5175fec39274ed0b9c99645484fd93d1716ef4310",
            "x86_64-pc-windows-msvc": "24741066da6f35a7ff67bee65ce82eae870d84e1181843e64a7076d1571e95af",
            "x86_64-unknown-linux-gnu": "da50b87d1ec42b3cb577dfd22a3655e43a53150f4f98a4bfb40757c9d7839ab5",
        },
        "strip_prefix": "python",
    },
    "3.11.4": {
        "url": "20230726/cpython-{python_version}+20230726-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "cb6d2948384a857321f2aa40fa67744cd9676a330f08b6dad7070bda0b6120a4",
            "aarch64-unknown-linux-gnu": "2e84fc53f4e90e11963281c5c871f593abcb24fc796a50337fa516be99af02fb",
            "ppc64le-unknown-linux-gnu": "df7b92ed9cec96b3bb658fb586be947722ecd8e420fb23cee13d2e90abcfcf25",
            "s390x-unknown-linux-gnu": "e477f0749161f9aa7887964f089d9460a539f6b4a8fdab5166f898210e1a87a4",
            "x86_64-apple-darwin": "47e1557d93a42585972772e82661047ca5f608293158acb2778dccf120eabb00",
            "x86_64-pc-windows-msvc": "878614c03ea38538ae2f758e36c85d2c0eb1eaaca86cd400ff8c76693ee0b3e1",
            "x86_64-unknown-linux-gnu": "e26247302bc8e9083a43ce9e8dd94905b40d464745b1603041f7bc9a93c65d05",
        },
        "strip_prefix": "python",
    },
    "3.11.5": {
        "url": "20230826/cpython-{python_version}+20230826-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "dab64b3580118ad2073babd7c29fd2053b616479df5c107d31fe2af1f45e948b",
            "aarch64-unknown-linux-gnu": "bb5c5d1ea0f199fe2d3f0996fff4b48ca6ddc415a3dbd98f50bff7fce48aac80",
            "ppc64le-unknown-linux-gnu": "14121b53e9c8c6d0741f911ae00102a35adbcf5c3cdf732687ef7617b7d7304d",
            "s390x-unknown-linux-gnu": "fe459da39874443579d6fe88c68777c6d3e331038e1fb92a0451879fb6beb16d",
            "x86_64-apple-darwin": "4a4efa7378c72f1dd8ebcce1afb99b24c01b07023aa6b8fea50eaedb50bf2bfc",
            "x86_64-pc-windows-msvc": "00f002263efc8aea896bcfaaf906b1f4dab3e5cd3db53e2b69ab9a10ba220b97",
            "x86_64-unknown-linux-gnu": "fbed6f7694b2faae5d7c401a856219c945397f772eea5ca50c6eb825cbc9d1e1",
        },
        "strip_prefix": "python",
    },
    "3.11.6": {
        "url": "20231002/cpython-{python_version}+20231002-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "916c35125b5d8323a21526d7a9154ca626453f63d0878e95b9f613a95006c990",
            "aarch64-unknown-linux-gnu": "3e26a672df17708c4dc928475a5974c3fb3a34a9b45c65fb4bd1e50504cc84ec",
            "ppc64le-unknown-linux-gnu": "7937035f690a624dba4d014ffd20c342e843dd46f89b0b0a1e5726b85deb8eaf",
            "s390x-unknown-linux-gnu": "f9f19823dba3209cedc4647b00f46ed0177242917db20fb7fb539970e384531c",
            "x86_64-apple-darwin": "178cb1716c2abc25cb56ae915096c1a083e60abeba57af001996e8bc6ce1a371",
            "x86_64-pc-windows-msvc": "3933545e6d41462dd6a47e44133ea40995bc6efeed8c2e4cbdf1a699303e95ea",
            "x86_64-unknown-linux-gnu": "ee37a7eae6e80148c7e3abc56e48a397c1664f044920463ad0df0fc706eacea8",
        },
        "strip_prefix": "python",
    },
    "3.11.7": {
        "url": "20240107/cpython-{python_version}+20240107-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "b042c966920cf8465385ca3522986b12d745151a72c060991088977ca36d3883",
            "aarch64-unknown-linux-gnu": "b102eaf865eb715aa98a8a2ef19037b6cc3ae7dfd4a632802650f29de635aa13",
            "ppc64le-unknown-linux-gnu": "b44e1b74afe75c7b19143413632c4386708ae229117f8f950c2094e9681d34c7",
            "s390x-unknown-linux-gnu": "49520e3ff494708020f306e30b0964f079170be83e956be4504f850557378a22",
            "x86_64-apple-darwin": "a0e615eef1fafdc742da0008425a9030b7ea68a4ae4e73ac557ef27b112836d4",
            "x86_64-pc-windows-msvc": "67077e6fa918e4f4fd60ba169820b00be7c390c497bf9bc9cab2c255ea8e6f3e",
            "x86_64-unknown-linux-gnu": "4a51ce60007a6facf64e5495f4cf322e311ba9f39a8cd3f3e4c026eae488e140",
        },
        "strip_prefix": "python",
    },
    "3.11.8": {
        "url": "20240224/cpython-{python_version}+20240224-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "389a51139f5abe071a0d70091ca5df3e7a3dfcfcbe3e0ba6ad85fb4c5638421e",
            "aarch64-unknown-linux-gnu": "389b9005fb78dd5a6f68df5ea45ab7b30d9a4b3222af96999e94fd20d4ad0c6a",
            "ppc64le-unknown-linux-gnu": "eb2b31f8e50309aae493c6a359c32b723a676f07c641f5e8fe4b6aa4dbb50946",
            "s390x-unknown-linux-gnu": "844f64f4c16e24965778281da61d1e0e6cd1358a581df1662da814b1eed096b9",
            "x86_64-apple-darwin": "097f467b0c36706bfec13f199a2eaf924e668f70c6e2bd1f1366806962f7e86e",
            "x86_64-pc-windows-msvc": "b618f1f047349770ee1ef11d1b05899840abd53884b820fd25c7dfe2ec1664d4",
            "x86_64-unknown-linux-gnu": "94e13d0e5ad417035b80580f3e893a72e094b0900d5d64e7e34ab08e95439987",
        },
        "strip_prefix": "python",
    },
    "3.11.9": {
        "url": "20240726/cpython-{python_version}+20240726-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "cbdac9462bab9671c8e84650e425d3f43b775752a930a2ef954a0d457d5c00c3",
            "aarch64-unknown-linux-gnu": "4d17cf988abe24449d649aad3ef974091ab76807904d41839907061925b4c9e3",
            "ppc64le-unknown-linux-gnu": "fc4f3c9ef9bfac2ed0282126ff376e544697ad04a5408d6429d46899d7d3bf21",
            "s390x-unknown-linux-gnu": "e69b66e53e926460df044f44846eef3fea642f630e829719e1a4112fc370dc56",
            "x86_64-apple-darwin": "dc3174666a30f4c38d04e79a80c3159b4b3aa69597c4676701c8386696811611",
            "x86_64-pc-windows-msvc": "f694be48bdfec1dace6d69a19906b6083f4dd7c7c61f1138ba520e433e5598f8",
            "x86_64-unknown-linux-gnu": "f6e955dc9ddfcad74e77abe6f439dac48ebca14b101ed7c85a5bf3206ed2c53d",
        },
        "strip_prefix": "python",
    },
    "3.11.10": {
        "url": "20241016/cpython-{python_version}+20241016-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "5a69382da99c4620690643517ca1f1f53772331b347e75f536088c42a4cf6620",
            "aarch64-unknown-linux-gnu": "803e49259280af0f5466d32829cd9d65a302b0226e424b3f0b261f9daf6aee8f",
            "ppc64le-unknown-linux-gnu": "92b666d103902001322f42badbd68da92adc5cebb826af9c1c906c33166e2f34",
            "s390x-unknown-linux-gnu": "6d584317651c1ad4a857cb32d1999707e8bb3046fcb2f156d80381814fa19fde",
            "x86_64-apple-darwin": "1e23ffe5bc473e1323ab8f51464da62d77399afb423babf67f8e13c82b69c674",
            "x86_64-pc-windows-msvc": "647b66ff4552e70aec3bf634dd470891b4a2b291e8e8715b3bdb162f577d4c55",
            "x86_64-unknown-linux-gnu": "8b50a442b04724a24c1eebb65a36a0c0e833d35374dbdf9c9470d8a97b164cd9",
            "x86_64-unknown-linux-musl": "d36fc77a8dd76155a7530f6235999a693b9e7c48aa11afeb5610a091cae5aa6f",
        },
        "strip_prefix": "python",
    },
    "3.11.13": {
        "url": "20250702/cpython-{python_version}+20250702-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "01167ac2c7336ff48a96e8dba30d92f29822a98e5ef27959178498b5a0de61da",
            "aarch64-unknown-linux-gnu": "42c99f013117255edcbe7a367694941f1ac096fd9e9a7d7c0d18d09551181930",
            "ppc64le-unknown-linux-gnu": "154ad77f7f552ab5f2ae07446eaccf6651db85db7403388c4439c6e43139d05e",
            "riscv64-unknown-linux-gnu": "e800cd1651bf2ce0be28541377228258fbe9a9a1fe87633d5fc8c6cb47262525",
            "s390x-unknown-linux-gnu": "5c6ce40240d92d9a3af4d49364205ce57bd4e73ba5274abcd3f20b85a0a88df9",
            "x86_64-apple-darwin": "b5955f7a951f8aa8755b35a1b3175968fc2b4bff54b9edffc6225c791305c4e6",
            "x86_64-pc-windows-msvc": "b68b7314e15f5d479acce2e9385a47f6ed978edc838dbb104175db889b349818",
            "aarch64-pc-windows-msvc": "ea81e436ac20b894f2070468f3323e69d4cb1a0e4e12bc14bb702a861f7a323d",
            "x86_64-unknown-linux-gnu": "e04944e70637f9d82022c9a41ae31de306b0d5bbd3fb64b9eb3261b8b5e0b30c",
            "x86_64-unknown-linux-musl": "69aeea0c21b994874d8481c39b9ba2683cbc7f6ec9cff964e1ea821f5ae4fc31",
        },
        "strip_prefix": "python",
    },
    "3.12.0": {
        "url": "20231002/cpython-{python_version}+20231002-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "4734a2be2becb813830112c780c9879ac3aff111a0b0cd590e65ec7465774d02",
            "aarch64-unknown-linux-gnu": "bccfe67cf5465a3dfb0336f053966e2613a9bc85a6588c2fcf1366ef930c4f88",
            "ppc64le-unknown-linux-gnu": "b5dae075467ace32c594c7877fe6ebe0837681f814601d5d90ba4c0dfd87a1f2",
            "s390x-unknown-linux-gnu": "5681621349dd85d9726d1b67c84a9686ce78f72e73a6f9e4cc4119911655759e",
            "x86_64-apple-darwin": "5a9e88c8aa52b609d556777b52ebde464ae4b4f77e4aac4eb693af57395c9abf",
            "x86_64-pc-windows-msvc": "facfaa1fbc8653f95057f3c4a0f8aa833dab0e0b316e24ee8686bc761d4b4f8d",
            "x86_64-unknown-linux-gnu": "e51a5293f214053ddb4645b2c9f84542e2ef86870b8655704367bd4b29d39fe9",
        },
        "strip_prefix": "python",
    },
    "3.12.1": {
        "url": "20240107/cpython-{python_version}+20240107-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "f93f8375ca6ac0a35d58ff007043cbd3a88d9609113f1cb59cf7c8d215f064af",
            "aarch64-unknown-linux-gnu": "236533ef20e665007a111c2f36efb59c87ae195ad7dca223b6dc03fb07064f0b",
            "ppc64le-unknown-linux-gnu": "78051f0d1411ee62bc2af5edfccf6e8400ac4ef82887a2affc19a7ace6a05267",
            "s390x-unknown-linux-gnu": "60631211c701f8d2c56e5dd7b154e68868128a019b9db1d53a264f56c0d4aee2",
            "x86_64-apple-darwin": "eca96158c1568dedd9a0b3425375637a83764d1fa74446438293089a8bfac1f8",
            "x86_64-pc-windows-msvc": "fd5a9e0f41959d0341246d3643f2b8794f638adc0cec8dd5e1b6465198eae08a",
            "x86_64-unknown-linux-gnu": "74e330b8212ca22fd4d9a2003b9eec14892155566738febc8e5e572f267b9472",
        },
        "strip_prefix": "python",
    },
    "3.12.2": {
        "url": "20240224/cpython-{python_version}+20240224-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "01c064c00013b0175c7858b159989819ead53f4746d40580b5b0b35b6e80fba6",
            "aarch64-unknown-linux-gnu": "e52550379e7c4ac27a87de832d172658bc04150e4e27d4e858e6d8cbb96fd709",
            "ppc64le-unknown-linux-gnu": "74bc02c4bbbd26245c37b29b9e12d0a9c1b7ab93477fed8b651c988b6a9a6251",
            "s390x-unknown-linux-gnu": "ecd6b0285e5eef94deb784b588b4b425a15a43ae671bf206556659dc141a9825",
            "x86_64-apple-darwin": "a53a6670a202c96fec0b8c55ccc780ea3af5307eb89268d5b41a9775b109c094",
            "x86_64-pc-windows-msvc": "1e5655a6ccb1a64a78460e4e3ee21036c70246800f176a6c91043a3fe3654a3b",
            "x86_64-unknown-linux-gnu": "57a37b57f8243caa4cdac016176189573ad7620f0b6da5941c5e40660f9468ab",
        },
        "strip_prefix": "python",
    },
    "3.12.3": {
        "url": "20240415/cpython-{python_version}+20240415-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "ccc40e5af329ef2af81350db2a88bbd6c17b56676e82d62048c15d548401519e",
            "aarch64-unknown-linux-gnu": "ec8126de97945e629cca9aedc80a29c4ae2992c9d69f2655e27ae73906ba187d",
            "ppc64le-unknown-linux-gnu": "c5dcf08b8077e617d949bda23027c49712f583120b3ed744f9b143da1d580572",
            "s390x-unknown-linux-gnu": "872fc321363b8cdd826fd2cb1adfd1ceb813bc1281f9d410c1c2c4e177e8df86",
            "x86_64-apple-darwin": "c37a22fca8f57d4471e3708de6d13097668c5f160067f264bb2b18f524c890c8",
            "x86_64-pc-windows-msvc": "f7cfa4ad072feb4578c8afca5ba9a54ad591d665a441dd0d63aa366edbe19279",
            "x86_64-unknown-linux-gnu": "a73ba777b5d55ca89edef709e6b8521e3f3d4289581f174c8699adfb608d09d6",
        },
        "strip_prefix": "python",
    },
    "3.12.4": {
        "url": "20240726/cpython-{python_version}+20240726-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "1801025e825c04b3907e4ef6220a13607bc0397628c9485897073110ef7fde15",
            "aarch64-unknown-linux-gnu": "a098b18b7e9fea0c66867b76c0124fce9465765017572b2e7b522154c87c78d7",
            "ppc64le-unknown-linux-gnu": "04011c4c5b7fe34b0b895edf4ad8748e410686c1d69aaee11d6688d481023bcb",
            "s390x-unknown-linux-gnu": "8f8f3e29cf0c2facdbcfee70660939fda7667ac24fee8656d3388fc72f3acc7c",
            "x86_64-apple-darwin": "4c325838c1b0ed13698506fcd515be25c73dcbe195f8522cf98f9148a97601ed",
            "x86_64-pc-windows-msvc": "74309b0f322716409883d38c621743ea7fa0376eb00927b8ee1e1671d3aff450",
            "x86_64-unknown-linux-gnu": "e133dd6fc6a2d0033e2658637cc22e9c95f9d7073b80115037ee1f16417a54ac",
        },
        "strip_prefix": "python",
    },
    "3.12.7": {
        "url": "20241016/cpython-{python_version}+20241016-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "4c18852bf9c1a11b56f21bcf0df1946f7e98ee43e9e4c0c5374b2b3765cf9508",
            "aarch64-unknown-linux-gnu": "bba3c6be6153f715f2941da34f3a6a69c2d0035c9c5396bc5bb68c6d2bd1065a",
            "ppc64le-unknown-linux-gnu": "0a1d1d92e33a969bd2f40a80af53c97b6c0cc1060d384ceff50ff801593bf9d6",
            "s390x-unknown-linux-gnu": "935676a0c960b552f95e9ac2e1e385de5de4b34038ff65ffdc688838f1189c17",
            "x86_64-apple-darwin": "60c5271e7edc3c2ab47440b7abf4ed50fbc693880b474f74f05768f5b657045a",
            "x86_64-pc-windows-msvc": "f05531bff16fa77b53be0776587b97b466070e768e6d5920894de988bdcd547a",
            "x86_64-unknown-linux-gnu": "43576f7db1033dd57b900307f09c2e86f371152ac8a2607133afa51cbfc36064",
            "x86_64-unknown-linux-musl": "5ed4a4078db3cbac563af66403aaa156cd6e48831d90382a1820db2b120627b5",
        },
        "strip_prefix": "python",
    },
    "3.12.8": {
        "url": "20241206/cpython-{python_version}+20241206-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "e3c4aa607717b23903ca2650d5c3ee24f89b97543e2db2b0f463bddc7a9e92f3",
            "aarch64-unknown-linux-gnu": "ce674b55442b732973afb2932c281bb1ded4ad7e22bcf9b07071165770758c7e",
            "ppc64le-unknown-linux-gnu": "b7214790b273de9ed0532420054b72ba1393d62d2fc844ec55ade193771bd90c",
            "s390x-unknown-linux-gnu": "73102f5dbd7d1e7e9c2f2c80aedf2893d99a7fa407f6674ec8b2f57ba07daee5",
            "x86_64-apple-darwin": "3ba35c706577d755e8e52a4c161a042464577c0e695e2a605362fa469e26de10",
            "x86_64-pc-windows-msvc": "767b4be3ddf6b99e5ade519789c1615c191d8cf99d5aff4685cc18b48931f1e6",
            "x86_64-unknown-linux-gnu": "b9d6ee5ddac1198e72d53112698773fc8bb597de095592eb849ca794306699ba",
            "x86_64-unknown-linux-musl": "6f305888703691dd04cfff85284d23ea0b0146ed7c4415e472f1fb72b3f32cdf",
        },
        "strip_prefix": "python",
    },
    "3.12.9": {
        "url": "20250317/cpython-{python_version}+20250317-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "7c7fd9809da0382a601a79287b5d62d61ce0b15f5a5ee836233727a516e85381",
            "aarch64-unknown-linux-gnu": "00c6bf9acef21ac741fea24dc449d0149834d30e9113429e50a95cce4b00bb80",
            "ppc64le-unknown-linux-gnu": "25d77599dfd5849f17391d92da0da99079e4e94f19a881f763f5cc62530ef7e1",
            "riscv64-unknown-linux-gnu": "e97ab0fdf443b302c56a52b4fd08f513bf3be66aa47263f0f9df3c6e60e05f2e",
            "s390x-unknown-linux-gnu": "7492d079ffa8425c8f6c58e43b237c37e3fb7b31e2e14635927bb4d3397ba21e",
            "x86_64-apple-darwin": "1ee1b1bb9fbce5c145c4bec9a3c98d7a4fa22543e09a7c1d932bc8599283c2dc",
            "x86_64-pc-windows-msvc": "d15361fd202dd74ae9c3eece1abdab7655f1eba90bf6255cad1d7c53d463ed4d",
            "x86_64-unknown-linux-gnu": "ef382fb88cbb41a3b0801690bd716b8a1aec07a6c6471010bcc6bd14cd575226",
            "x86_64-unknown-linux-musl": "94e3837da1adf9964aab2d6047b33f70167de3096d1f9a2d1fa9340b1bbf537d",
        },
        "strip_prefix": "python",
    },
    "3.12.11": {
        "url": "20250702/cpython-{python_version}+20250702-{platform}-{build}.tar.gz",
        "sha256": {
            "aarch64-apple-darwin": "5f8e9480d0981268961e63729de1c9b037cabfe030949943be293f0d3e3e7703",
            "aarch64-unknown-linux-gnu": "a63c9d7d712ca33e2fc57d9bf3ebf98c8f574f23b3eeeed44faf3b4b08d8a9b8",
            "aarch64-pc-windows-msvc": "4d3736640d8916da6d69060e90cad607903e4f1d8dc0f284fd475f04f312712e",
            "ppc64le-unknown-linux-gnu": "76dc3accfc8515fe7e11b5f1af26734bc7c0a075890a9c85dc1c7b6d0421ebbc",
            "riscv64-unknown-linux-gnu": "d80dd210da941583c3166ff5a762bfd3f3211ecb2968eee8ec497548ef970682",
            "s390x-unknown-linux-gnu": "a7d0778ae32c1d882eb3354877c31298010cde2107ecf60b7b75dcabe7ddd8ad",
            "x86_64-apple-darwin": "f7a7a70fc7199cc37fd04bc1375b4cd7f44fb05128965e72b589fe112029cab8",
            "x86_64-pc-windows-msvc": "19bdfa7362faf6869c376976e0296b597ce2d70e68ea7b357c6f68c79ad9aa9e",
            "x86_64-unknown-linux-gnu": "0919f8b5311765b4cf1342371724d7bf2a6eaf51f15f5cb2b9ad5fd0ee54271c",
            "x86_64-unknown-linux-musl": "64308b6133ae57de6d7c84b9caf6b084d1ccabf4b617c8a88a08fa57da66df16",
        },
        "strip_prefix": "python",
    },
    "3.13.0": {
        "url": "20241016/cpython-{python_version}+20241016-{platform}-{build}.{ext}",
        "sha256": {
            "aarch64-apple-darwin": "31397953849d275aa2506580f3fa1cb5a85b6a3d392e495f8030e8b6412f5556",
            "aarch64-unknown-linux-gnu": "e8378c0162b2e0e4cc1f62b29443a3305d116d09583304dbb0149fecaff6347b",
            "ppc64le-unknown-linux-gnu": "fc4b7f27c4e84c78f3c8e6c7f8e4023e4638d11f1b36b6b5ce457b1926cebb53",
            "s390x-unknown-linux-gnu": "66b19e6a07717f6cfcd3a8ca953f0a2eaa232291142f3d26a8d17c979ec0f467",
            "x86_64-apple-darwin": "cff1b7e7cd26f2d47acac1ad6590e27d29829776f77e8afa067e9419f2f6ce77",
            "x86_64-pc-windows-msvc": "b25926e8ce4164cf103bacc4f4d154894ea53e07dd3fdd5ebb16fb1a82a7b1a0",
            "x86_64-unknown-linux-gnu": "2c8cb15c6a2caadaa98af51df6fe78a8155b8471cb3dd7b9836038e0d3657fb4",
            "x86_64-unknown-linux-musl": "2f61ee3b628a56aceea63b46c7afe2df3e22a61da706606b0c8efda57f953cf4",
            "aarch64-apple-darwin-freethreaded": "efc2e71c0e05bc5bedb7a846e05f28dd26491b1744ded35ed82f8b49ccfa684b",
            "aarch64-unknown-linux-gnu-freethreaded": "59b50df9826475d24bb7eff781fa3949112b5e9c92adb29e96a09cdf1216d5bd",
            "ppc64le-unknown-linux-gnu-freethreaded": "1217efa5f4ce67fcc9f7eb64165b1bd0912b2a21bc25c1a7e2cb174a21a5df7e",
            "s390x-unknown-linux-gnu-freethreaded": "6c3e1e4f19d2b018b65a7e3ef4cd4225c5b9adfbc490218628466e636d5c4b8c",
            "x86_64-apple-darwin-freethreaded": "2e07dfea62fe2215738551a179c87dbed1cc79d1b3654f4d7559889a6d5ce4eb",
            "x86_64-pc-windows-msvc-freethreaded": "bfd89f9acf866463bc4baf01733da5e767d13f5d0112175a4f57ba91f1541310",
            "x86_64-unknown-linux-gnu-freethreaded": "a73adeda301ad843cce05f31a2d3e76222b656984535a7b87696a24a098b216c",
        },
        "strip_prefix": {
            "aarch64-apple-darwin": "python",
            "aarch64-unknown-linux-gnu": "python",
            "ppc64le-unknown-linux-gnu": "python",
            "s390x-unknown-linux-gnu": "python",
            "x86_64-apple-darwin": "python",
            "x86_64-pc-windows-msvc": "python",
            "x86_64-unknown-linux-gnu": "python",
            "x86_64-unknown-linux-musl": "python",
            "aarch64-apple-darwin-freethreaded": "python/install",
            "aarch64-unknown-linux-gnu-freethreaded": "python/install",
            "ppc64le-unknown-linux-gnu-freethreaded": "python/install",
            "s390x-unknown-linux-gnu-freethreaded": "python/install",
            "x86_64-apple-darwin-freethreaded": "python/install",
            "x86_64-pc-windows-msvc-freethreaded": "python/install",
            "x86_64-unknown-linux-gnu-freethreaded": "python/install",
        },
    },
    "3.13.1": {
        "url": "20241205/cpython-{python_version}+20241205-{platform}-{build}.{ext}",
        "sha256": {
            "aarch64-apple-darwin": "88b88b609129c12f4b3841845aca13230f61e97ba97bd0fb28ee64b0e442a34f",
            "aarch64-unknown-linux-gnu": "fdfa86c2746d2ae700042c461846e6c37f70c249925b58de8cd02eb8d1423d4e",
            "ppc64le-unknown-linux-gnu": "27b20b3237c55430ca1304e687d021f88373f906249f9cd272c5ff2803d5e5c3",
            "s390x-unknown-linux-gnu": "7d0187e20cb5e36c689eec27e4d3de56d8b7f1c50dc5523550fc47377801521f",
            "x86_64-apple-darwin": "47eef6efb8664e2d1d23a7cdaf56262d784f8ace48f3bfca1b183e95a49888d6",
            "x86_64-pc-windows-msvc": "f51f0493a5f979ff0b8d8c598a8d74f2a4d86a190c2729c85e0af65c36a9cbbe",
            "x86_64-unknown-linux-gnu": "242b2727df6c1e00de6a9f0f0dcb4562e168d27f428c785b0eb41a6aeb34d69a",
            "x86_64-unknown-linux-musl": "76b30c6373b9c0aa2ba610e07da02f384aa210ac79643da38c66d3e6171c6ef5",
            "aarch64-apple-darwin-freethreaded": "08f05618bdcf8064a7960b25d9ba92155447c9b08e0cf2f46a981e4c6a1bb5a5",
            "aarch64-unknown-linux-gnu-freethreaded": "9f2fcb809f9ba6c7c014a8803073a88786701a98971135bce684355062e4bb35",
            "ppc64le-unknown-linux-gnu-freethreaded": "15ceea78dff78ca8ccaac8d9c54b808af30daaa126f1f561e920a6896e098634",
            "s390x-unknown-linux-gnu-freethreaded": "ed3c6118d1d12603309c930e93421ac7a30a69045ffd43006f63ecf71d72c317",
            "x86_64-apple-darwin-freethreaded": "dc780fecd215d2cc9e573abf1e13a175fcfa8f6efd100ef888494a248a16cda8",
            "x86_64-pc-windows-msvc-freethreaded": "7537b2ab361c0eabc0eabfca9ffd9862d7f5f6576eda13b97e98aceb5eea4fd3",
            "x86_64-unknown-linux-gnu-freethreaded": "9ec1b81213f849d91f5ebe6a16196e85cd6ff7c05ca823ce0ab7ba5b0e9fee84",
        },
        "strip_prefix": {
            "aarch64-apple-darwin": "python",
            "aarch64-unknown-linux-gnu": "python",
            "ppc64le-unknown-linux-gnu": "python",
            "s390x-unknown-linux-gnu": "python",
            "x86_64-apple-darwin": "python",
            "x86_64-pc-windows-msvc": "python",
            "x86_64-unknown-linux-gnu": "python",
            "x86_64-unknown-linux-musl": "python",
            "aarch64-apple-darwin-freethreaded": "python/install",
            "aarch64-unknown-linux-gnu-freethreaded": "python/install",
            "ppc64le-unknown-linux-gnu-freethreaded": "python/install",
            "s390x-unknown-linux-gnu-freethreaded": "python/install",
            "x86_64-apple-darwin-freethreaded": "python/install",
            "x86_64-pc-windows-msvc-freethreaded": "python/install",
            "x86_64-unknown-linux-gnu-freethreaded": "python/install",
        },
    },
    "3.13.2": {
        "url": "20250317/cpython-{python_version}+20250317-{platform}-{build}.{ext}",
        "sha256": {
            "aarch64-apple-darwin": "faa44274a331eb39786362818b21b3a4e74514e8805000b20b0e55c590cecb94",
            "aarch64-unknown-linux-gnu": "9c67260446fee6ea706dad577a0b32936c63f449c25d66e4383d5846b2ab2e36",
            "ppc64le-unknown-linux-gnu": "345b53d2f86c9dbd7f1320657cb227ff9a42ef63ff21f129abbbc8c82a375147",
            "riscv64-unknown-linux-gnu": "172d22b2330737f3a028ea538ffe497c39a066a8d3200b22dd4d177a3332ad85",
            "s390x-unknown-linux-gnu": "ec3b16ea8a97e3138acec72bc5ff35949950c62c8994a8ec8e213fd93f0e806b",
            "x86_64-apple-darwin": "ee4526e84b5ce5b11141c50060b385320f2773616249a741f90c96d460ce8e8f",
            "x86_64-pc-windows-msvc": "84d7b52f3558c8e35c670a4fa14080c75e3ec584adfae49fec8b51008b75b21e",
            "x86_64-unknown-linux-gnu": "db011f0cd29cab2291584958f4e2eb001b0e6051848d89b38a2dc23c5c54e512",
            "x86_64-unknown-linux-musl": "00bb2d629f7eacbb5c6b44dc04af26d1f1da64cee3425b0d8eb5135a93830296",
            "aarch64-apple-darwin-freethreaded": "c98c9c977e6fa05c3813bd49f3553904d89d60fed27e2e36468da7afa1d6d5e2",
            "aarch64-unknown-linux-gnu-freethreaded": "b8635e59e3143fd17f19a3dfe8ccc246ee6587c87da359bd1bcab35eefbb5f19",
            "ppc64le-unknown-linux-gnu-freethreaded": "6ae8fa44cb2edf4ab49cff1820b53c40c10349c0f39e11b8cd76ce7f3e7e1def",
            "riscv64-unknown-linux-gnu-freethreaded": "2af1b8850c52801fb6189e7a17a51e0c93d9e46ddefcca72247b76329c97d02a",
            "s390x-unknown-linux-gnu-freethreaded": "c074144cc80c2af32c420b79a9df26e8db405212619990c1fbdd308bd75afe3f",
            "x86_64-apple-darwin-freethreaded": "0d73e4348d8d4b5159058609d2303705190405b485dd09ad05d870d7e0f36e0f",
            "x86_64-pc-windows-msvc-freethreaded": "c51b4845fda5421e044067c111192f645234081d704313f74ee77fa013a186ea",
            "x86_64-unknown-linux-gnu-freethreaded": "1aea5062614c036904b55c1cc2fb4b500b7f6f7a4cacc263f4888889d355eef8",
        },
        "strip_prefix": {
            "aarch64-apple-darwin": "python",
            "aarch64-unknown-linux-gnu": "python",
            "ppc64le-unknown-linux-gnu": "python",
            "s390x-unknown-linux-gnu": "python",
            "riscv64-unknown-linux-gnu": "python",
            "x86_64-apple-darwin": "python",
            "x86_64-pc-windows-msvc": "python",
            "x86_64-unknown-linux-gnu": "python",
            "x86_64-unknown-linux-musl": "python",
            "aarch64-apple-darwin-freethreaded": "python/install",
            "aarch64-unknown-linux-gnu-freethreaded": "python/install",
            "ppc64le-unknown-linux-gnu-freethreaded": "python/install",
            "riscv64-unknown-linux-gnu-freethreaded": "python/install",
            "s390x-unknown-linux-gnu-freethreaded": "python/install",
            "x86_64-apple-darwin-freethreaded": "python/install",
            "x86_64-pc-windows-msvc-freethreaded": "python/install",
            "x86_64-unknown-linux-gnu-freethreaded": "python/install",
        },
    },
    "3.13.4": {
        "url": "20250610/cpython-{python_version}+20250610-{platform}-{build}.{ext}",
        "sha256": {
            "aarch64-apple-darwin": "c2ce6601b2668c7bd1f799986af5ddfbff36e88795741864aba6e578cb02ed7f",
            "aarch64-unknown-linux-gnu": "3c2596ece08ffe17e11bc1f27aeb4ce1195d2490a83d695d36ef4933d5c5ca53",
            "ppc64le-unknown-linux-gnu": "b3cc13ee177b8db1d3e9b2eac413484e3c6a356f97d91dc59de8d3fd8cf79d6b",
            "riscv64-unknown-linux-gnu": "d1b989e57a9ce29f6c945eeffe0e9750c222fdd09e99d2f8d6b0d8532a523053",
            "s390x-unknown-linux-gnu": "d1d19fb01961ac6476712fdd6c5031f74c83666f6f11aa066207e9a158f7e3d8",
            "x86_64-apple-darwin": "79feb6ca68f3921d07af52d9db06cf134e6f36916941ea850ab0bc20f5ff638b",
            "x86_64-pc-windows-msvc": "29ac3585cc2dcfd79e3fe380c272d00e9d34351fc456e149403c86d3fea34057",
            "x86_64-unknown-linux-gnu": "44e5477333ebca298a7a0a316985c6c3533b8645f92a83f7f73c44033832bf32",
            "x86_64-unknown-linux-musl": "a3afbfa94b9ff4d9fc426b47eb3c8446cada535075b8d51b7bdc9d9ab9911fc2",
            "aarch64-apple-darwin-freethreaded": "278dccade56b4bbeecb9a613b77012cf5c1433a5e9b8ef99230d5e61f31d9e02",
            "aarch64-unknown-linux-gnu-freethreaded": "b1c1bd6ab9ef95b464d92a6a911cef1a8d9f0b0f6a192f694ef18ed15d882edf",
            "ppc64le-unknown-linux-gnu-freethreaded": "ed66ae213a62b286b9b7338b816ccd2815f5248b7a28a185dc8159fe004149ae",
            "riscv64-unknown-linux-gnu-freethreaded": "913264545215236660e4178bc3e5b57a20a444a8deb5c11680c95afc960b4016",
            "s390x-unknown-linux-gnu-freethreaded": "7556a38ab5e507c1ec22bc38f9859982bc956cab7f4de05a2faac114feb306db",
            "x86_64-apple-darwin-freethreaded": "64ab7ac8c88002d9ba20a92f72945bfa350268e944a7922500af75d20330574d",
            "x86_64-pc-windows-msvc-freethreaded": "9457504547edb2e0156bf76b53c7e4941c7f61c0eff9fd5f4d816d3df51c58e3",
            "x86_64-unknown-linux-gnu-freethreaded": "864df6e6819e8f8e855ce30f34410fdc5867d0616e904daeb9a40e5806e970d7",
        },
        "strip_prefix": {
            "aarch64-apple-darwin": "python",
            "aarch64-unknown-linux-gnu": "python",
            "ppc64le-unknown-linux-gnu": "python",
            "s390x-unknown-linux-gnu": "python",
            "riscv64-unknown-linux-gnu": "python",
            "x86_64-apple-darwin": "python",
            "x86_64-pc-windows-msvc": "python",
            "x86_64-unknown-linux-gnu": "python",
            "x86_64-unknown-linux-musl": "python",
            "aarch64-apple-darwin-freethreaded": "python/install",
            "aarch64-unknown-linux-gnu-freethreaded": "python/install",
            "ppc64le-unknown-linux-gnu-freethreaded": "python/install",
            "riscv64-unknown-linux-gnu-freethreaded": "python/install",
            "s390x-unknown-linux-gnu-freethreaded": "python/install",
            "x86_64-apple-darwin-freethreaded": "python/install",
            "x86_64-pc-windows-msvc-freethreaded": "python/install",
            "x86_64-unknown-linux-gnu-freethreaded": "python/install",
        },
    },
    "3.13.5": {
        "url": "20250702/cpython-{python_version}+20250702-{platform}-{build}.{ext}",
        "sha256": {
            "aarch64-apple-darwin": "66577414e9f4b0caa116a8e15fa50306db91bce13d49278079bb22adaeefb1fa",
            "aarch64-unknown-linux-gnu": "272a8817921856d7ac47f44c076fb62fbaf5649aa1d97b2d67a3a6adee969ff0",
            "ppc64le-unknown-linux-gnu": "7bfa9fed4b3a1e37b4879d51d82bce521bd999ec450c91f7787188ce1cafd76c",
            "riscv64-unknown-linux-gnu": "deebdf17f7c153708b88ef2ae8b643635a02a9e9bdf4f0435e8c6cd15b37b248",
            "s390x-unknown-linux-gnu": "38c10133adfc9ebe9d2e74f7047ab6763b05c978be2dc772e1deb2978504084f",
            "x86_64-apple-darwin": "0682afbb238b4762b8f5e383fe19cc52969c780871016c50d4cb7088a536167c",
            "x86_64-pc-windows-msvc": "f11f915437250657019c71adb81ec523d2932c2c3ea4441b592aa3bdce0e7ef7",
            "aarch64-pc-windows-msvc": "f2de020035f125a47aee320f722b0ced19862ba1e1412392791cffa9cb174d0c",
            "aarch64-pc-windows-msvc-freethreaded": "97041594d903d6a1de1e55e9a3e5c613384aa7b900a93096f372732d9953f52a",
            "x86_64-unknown-linux-gnu": "9f5d5260f333fcb5372ec681851d92ddac79a33362aa85626b6cc96ffe75eeef",
            "x86_64-unknown-linux-musl": "7856fd505e311d1a4c24e429ac5ef0ff6ca7a2005c3a7eff1fe204524a6f45aa",
            "aarch64-apple-darwin-freethreaded": "52e582cc89d654c565297b4ff9c3bd4bed5c3e81cad46f41c62485e700faf8bd",
            "aarch64-unknown-linux-gnu-freethreaded": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            "ppc64le-unknown-linux-gnu-freethreaded": "c65c75edb450de830f724afdc774a215c2d3255097e0d670f709d2271fd6fd52",
            "riscv64-unknown-linux-gnu-freethreaded": "716e6e3fad24fb9931b93005000152dd9da4c3343b88ca54b5c01a7ab879d734",
            "s390x-unknown-linux-gnu-freethreaded": "27276aee426a51f4165fac49391aedc5a9e301ae217366c77b65826122bb30fc",
            "x86_64-apple-darwin-freethreaded": "5aed6d5950514004149d514f81a1cd426ac549696a563b8e47d32f7eba3b4be3",
            "x86_64-pc-windows-msvc-freethreaded": "39e19dcb823a2ed47d9510753a642ba468802f1c5e15771c6c22814f4acada94",
            "x86_64-unknown-linux-gnu-freethreaded": "f5eb29604c0b7afa2097fca094a06eb7a1f3ca4e194264c34f342739cae78202",
        },
        "strip_prefix": {
            "aarch64-apple-darwin": "python",
            "aarch64-unknown-linux-gnu": "python",
            "ppc64le-unknown-linux-gnu": "python",
            "s390x-unknown-linux-gnu": "python",
            "riscv64-unknown-linux-gnu": "python",
            "x86_64-apple-darwin": "python",
            "x86_64-pc-windows-msvc": "python",
            "x86_64-unknown-linux-gnu": "python",
            "x86_64-unknown-linux-musl": "python",
            "aarch64-apple-darwin-freethreaded": "python/install",
            "aarch64-unknown-linux-gnu-freethreaded": "python/install",
            "ppc64le-unknown-linux-gnu-freethreaded": "python/install",
            "riscv64-unknown-linux-gnu-freethreaded": "python/install",
            "s390x-unknown-linux-gnu-freethreaded": "python/install",
            "x86_64-apple-darwin-freethreaded": "python/install",
            "x86_64-pc-windows-msvc-freethreaded": "python/install",
            "aarch64-pc-windows-msvc": "python/install",
            "aarch64-pc-windows-msvc-freethreaded": "python/install",
            "x86_64-unknown-linux-gnu-freethreaded": "python/install",
        },
    },
    "3.14.0b3": {
        "url": "20250702/cpython-{python_version}+20250702-{platform}-{build}.{ext}",
        "sha256": {
            "aarch64-apple-darwin": "14af7a0c0a50f82cf75f79f4c02dc31c73c74032930a8337f83f3ae3bee4660f",
            "aarch64-unknown-linux-gnu": "013e2081c3e7e61932210ede84c9f05a4f6533f807287bab141d8abe77087ffd",
            "ppc64le-unknown-linux-gnu": "2118b6b9baad4f4283246b281183254620d18d8c95991dc5db810ab07ff41cee",
            "riscv64-unknown-linux-gnu": "7d11ccad5bff3085d8b3e725179d7e1f93cc8e4fb83391cb49bc4b29cf877153",
            "s390x-unknown-linux-gnu": "e3c90fb8cfe897ac96bb0b0d5de9f4512646b8ebd5c8b3123d9e31a96a0eac3c",
            "x86_64-apple-darwin": "8e9d640e5e7c49f8c67dfd2330bdd814f4c5de685abefbe91c639c0e0844c2bd",
            "x86_64-pc-windows-msvc": "cdab7856e2495ab4ed666354e9391435c8e45512e841ef8452da69a6e96caa96",
            "aarch64-pc-windows-msvc": "000fbc010e844bcd64330badb295da7b5b08b427357f463afc7e600988f7ecc6",
            "x86_64-unknown-linux-gnu": "00328c48cc07076a5b083575654761cdb07bc8b3bba864d3a225062722485bac",
            "x86_64-unknown-linux-musl": "a2fed85bc3d5415d2318a2eeb0cb9e6effb81667870ae568a08756838ad4926e",
            "aarch64-apple-darwin-freethreaded": "d19213021f5fd039d7021ccb41698cc99ca313064d7c1cc9b5ef8f831abb9961",
            "aarch64-unknown-linux-gnu-freethreaded": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            "ppc64le-unknown-linux-gnu-freethreaded": "1f093e0c3532e27744e3fb73a8c738355910b6bfa195039e4f73b4f48c1bc4fc",
            "riscv64-unknown-linux-gnu-freethreaded": "73162a5da31cc1e410d456496114f8e5ee7243bc7bbe0e087b1ea50f0fdc6774",
            "s390x-unknown-linux-gnu-freethreaded": "045017e60f1298111e8ccfec6afbe47abe56f82997258c8754009269a5343736",
            "x86_64-apple-darwin-freethreaded": "26ec6697bbb38c3fa6275e79e110854b2585914ca503c65916478e7ca8d0491b",
            "x86_64-pc-windows-msvc-freethreaded": "8de6235b29396e3b25fc3ade166c49506171ec464cda46987ef9641dd9a44071",
            "aarch64-pc-windows-msvc-freethreaded": "331816d79cd78eaadba5ae6cdd3a243771199d0ca07057e7a452158dd4a7edcc",
            "x86_64-unknown-linux-gnu-freethreaded": "081f0147d8f4479764d6a3819f67275be3306003366eda9ecb9ee844f2f611be",
        },
        "strip_prefix": {
            "aarch64-apple-darwin": "python",
            "aarch64-unknown-linux-gnu": "python",
            "ppc64le-unknown-linux-gnu": "python",
            "s390x-unknown-linux-gnu": "python",
            "riscv64-unknown-linux-gnu": "python",
            "x86_64-apple-darwin": "python",
            "x86_64-pc-windows-msvc": "python",
            "aarch64-pc-windows-msvc": "python",
            "x86_64-unknown-linux-gnu": "python",
            "x86_64-unknown-linux-musl": "python",
            "aarch64-apple-darwin-freethreaded": "python/install",
            "aarch64-unknown-linux-gnu-freethreaded": "python/install",
            "ppc64le-unknown-linux-gnu-freethreaded": "python/install",
            "riscv64-unknown-linux-gnu-freethreaded": "python/install",
            "s390x-unknown-linux-gnu-freethreaded": "python/install",
            "x86_64-apple-darwin-freethreaded": "python/install",
            "x86_64-pc-windows-msvc-freethreaded": "python/install",
            "aarch64-pc-windows-msvc-freethreaded": "python/install",
            "x86_64-unknown-linux-gnu-freethreaded": "python/install",
        },
    },
}

# buildifier: disable=unsorted-dict-items
MINOR_MAPPING = {
    "3.8": "3.8.20",
    "3.9": "3.9.23",
    "3.10": "3.10.18",
    "3.11": "3.11.13",
    "3.12": "3.12.11",
    "3.13": "3.13.5",
    "3.14": "3.14.0b3",
}

def _generate_platforms():
    is_libc_glibc = str(Label("//python/config_settings:_is_py_linux_libc_glibc"))
    is_libc_musl = str(Label("//python/config_settings:_is_py_linux_libc_musl"))

    platforms = {
        "aarch64-apple-darwin": platform_info(
            compatible_with = [
                "@platforms//os:macos",
                "@platforms//cpu:aarch64",
            ],
            os_name = MACOS_NAME,
            arch = "aarch64",
        ),
        "aarch64-pc-windows-msvc": platform_info(
            compatible_with = [
                "@platforms//os:windows",
                "@platforms//cpu:aarch64",
            ],
            os_name = WINDOWS_NAME,
            arch = "aarch64",
        ),
        "aarch64-unknown-linux-gnu": platform_info(
            compatible_with = [
                "@platforms//os:linux",
                "@platforms//cpu:aarch64",
            ],
            target_settings = [
                is_libc_glibc,
            ],
            os_name = LINUX_NAME,
            arch = "aarch64",
        ),
        "armv7-unknown-linux-gnu": platform_info(
            compatible_with = [
                "@platforms//os:linux",
                "@platforms//cpu:armv7",
            ],
            target_settings = [
                is_libc_glibc,
            ],
            os_name = LINUX_NAME,
            arch = "arm",
        ),
        "i386-unknown-linux-gnu": platform_info(
            compatible_with = [
                "@platforms//os:linux",
                "@platforms//cpu:i386",
            ],
            target_settings = [
                is_libc_glibc,
            ],
            os_name = LINUX_NAME,
            arch = "x86_32",
        ),
        "ppc64le-unknown-linux-gnu": platform_info(
            compatible_with = [
                "@platforms//os:linux",
                "@platforms//cpu:ppc",
            ],
            target_settings = [
                is_libc_glibc,
            ],
            os_name = LINUX_NAME,
            arch = "ppc",
        ),
        "riscv64-unknown-linux-gnu": platform_info(
            compatible_with = [
                "@platforms//os:linux",
                "@platforms//cpu:riscv64",
            ],
            target_settings = [
                is_libc_glibc,
            ],
            os_name = LINUX_NAME,
            arch = "riscv64",
        ),
        "s390x-unknown-linux-gnu": platform_info(
            compatible_with = [
                "@platforms//os:linux",
                "@platforms//cpu:s390x",
            ],
            target_settings = [
                is_libc_glibc,
            ],
            os_name = LINUX_NAME,
            arch = "s390x",
        ),
        "x86_64-apple-darwin": platform_info(
            compatible_with = [
                "@platforms//os:macos",
                "@platforms//cpu:x86_64",
            ],
            os_name = MACOS_NAME,
            arch = "x86_64",
        ),
        "x86_64-pc-windows-msvc": platform_info(
            compatible_with = [
                "@platforms//os:windows",
                "@platforms//cpu:x86_64",
            ],
            os_name = WINDOWS_NAME,
            arch = "x86_64",
        ),
        "x86_64-unknown-linux-gnu": platform_info(
            compatible_with = [
                "@platforms//os:linux",
                "@platforms//cpu:x86_64",
            ],
            target_settings = [
                is_libc_glibc,
            ],
            os_name = LINUX_NAME,
            arch = "x86_64",
        ),
        "x86_64-unknown-linux-musl": platform_info(
            compatible_with = [
                "@platforms//os:linux",
                "@platforms//cpu:x86_64",
            ],
            target_settings = [
                is_libc_musl,
            ],
            os_name = LINUX_NAME,
            arch = "x86_64",
        ),
    }

    is_freethreaded_yes = str(Label("//python/config_settings:_is_py_freethreaded_yes"))
    is_freethreaded_no = str(Label("//python/config_settings:_is_py_freethreaded_no"))
    return {
        p + suffix: platform_info(
            compatible_with = v.compatible_with,
            target_settings = [
                freethreadedness,
            ] + v.target_settings,
            os_name = v.os_name,
            arch = v.arch,
        )
        for p, v in platforms.items()
        for suffix, freethreadedness in {
            "": is_freethreaded_no,
            FREETHREADED: is_freethreaded_yes,
        }.items()
    }

PLATFORMS = _generate_platforms()

def get_release_info(platform, python_version, base_url = DEFAULT_RELEASE_BASE_URL, tool_versions = TOOL_VERSIONS):
    """Resolve the release URL for the requested interpreter version

    Args:
        platform: The platform string for the interpreter
        python_version: The version of the interpreter to get
        base_url: The URL to prepend to the 'url' attr in the tool_versions dict
        tool_versions: A dict listing the interpreter versions, their SHAs and URL

    Returns:
        A tuple of (filename, url, archive strip prefix, patches, patch_strip)
    """

    url = tool_versions[python_version]["url"]

    if type(url) == type({}):
        url = url[platform]

    if type(url) != type([]):
        url = [url]

    strip_prefix = tool_versions[python_version].get("strip_prefix", None)
    if type(strip_prefix) == type({}):
        strip_prefix = strip_prefix[platform]

    release_filename = None
    rendered_urls = []
    for u in url:
        p, _, _ = platform.partition(FREETHREADED)

        if FREETHREADED.lstrip("-") in platform:
            build = "{}+{}-full".format(
                FREETHREADED.lstrip("-"),
                {
                    "aarch64-apple-darwin": "pgo+lto",
                    "aarch64-pc-windows-msvc": "pgo",
                    "aarch64-unknown-linux-gnu": "lto",
                    "ppc64le-unknown-linux-gnu": "lto",
                    "riscv64-unknown-linux-gnu": "lto",
                    "s390x-unknown-linux-gnu": "lto",
                    "x86_64-apple-darwin": "pgo+lto",
                    "x86_64-pc-windows-msvc": "pgo",
                    "x86_64-unknown-linux-gnu": "pgo+lto",
                }[p],
            )
        else:
            build = INSTALL_ONLY

        if WINDOWS_NAME in platform and int(u.split("/")[0]) < 20250317:
            build = "shared-" + build

        release_filename = u.format(
            platform = p,
            python_version = python_version,
            build = build,
            ext = "tar.zst" if build.endswith("full") else "tar.gz",
        )
        if "://" in release_filename:  # is absolute url?
            rendered_urls.append(release_filename)
        else:
            rendered_urls.append("/".join([base_url, release_filename]))

    if release_filename == None:
        fail("release_filename should be set by now; were any download URLs given?")

    patches = tool_versions[python_version].get("patches", [])
    if type(patches) == type({}):
        if platform in patches.keys():
            patches = patches[platform]
        else:
            patches = []
    patch_strip = tool_versions[python_version].get("patch_strip", None)
    if type(patch_strip) == type({}):
        if platform in patch_strip.keys():
            patch_strip = patch_strip[platform]
        else:
            patch_strip = None

    return (release_filename, rendered_urls, strip_prefix, patches, patch_strip)

def gen_python_config_settings(name = ""):
    for platform in PLATFORMS.keys():
        native.config_setting(
            name = "{name}{platform}".format(name = name, platform = platform),
            flag_values = PLATFORMS[platform].flag_values,
            constraint_values = PLATFORMS[platform].compatible_with,
        )

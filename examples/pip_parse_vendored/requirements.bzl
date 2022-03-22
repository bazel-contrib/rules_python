"""Starlark representation of locked requirements.

@generated by rules_python pip_parse repository rule
from //:requirements.txt
"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@python39//:defs.bzl", "interpreter")
load("@rules_python//python/pip_install:pip_repository.bzl", "whl_library")

all_requirements = ["@pip_certifi//:pkg", "@pip_charset_normalizer//:pkg", "@pip_idna//:pkg", "@pip_requests//:pkg", "@pip_urllib3//:pkg"]

all_whl_requirements = ["@pip_certifi//:whl", "@pip_charset_normalizer//:whl", "@pip_idna//:whl", "@pip_requests//:whl", "@pip_urllib3//:whl"]

_packages = [("pip_certifi", "certifi==2021.10.8     --hash=sha256:78884e7c1d4b00ce3cea67b44566851c4343c120abd683433ce934a68ea58872     --hash=sha256:d62a0163eb4c2344ac042ab2bdf75399a71a2d8c7d47eac2e2ee91b9d6339569"), ("pip_charset_normalizer", "charset-normalizer==2.0.12     --hash=sha256:2857e29ff0d34db842cd7ca3230549d1a697f96ee6d3fb071cfa6c7393832597     --hash=sha256:6881edbebdb17b39b4eaaa821b438bf6eddffb4468cf344f09f89def34a8b1df"), ("pip_idna", "idna==3.3     --hash=sha256:84d9dd047ffa80596e0f246e2eab0b391788b0503584e8945f2368256d2735ff     --hash=sha256:9d643ff0a55b762d5cdb124b8eaa99c66322e2157b69160bc32796e824360e6d"), ("pip_requests", "requests==2.27.1     --hash=sha256:68d7c56fd5a8999887728ef304a6d12edc7be74f1cfa47714fc8b414525c9a61     --hash=sha256:f22fa1e554c9ddfd16e6e41ac79759e17be9e492b3587efa038054674760e72d"), ("pip_urllib3", "urllib3==1.26.9     --hash=sha256:44ece4d53fb1706f667c9bd1c648f5469a2ec925fcf3a776667042d645472c14     --hash=sha256:aabaf16477806a5e1dd19aa41f8c2b7950dd3c746362d7e3223dbe6de6ac448e")]
_config = {"enable_implicit_namespace_pkgs": False, "environment": {}, "extra_pip_args": [], "isolated": True, "pip_data_exclude": [], "python_interpreter": "python3", "python_interpreter_target": interpreter, "quiet": True, "repo": "pip", "repo_prefix": "pip_", "timeout": 600}
_annotations = {}

def _clean_name(name):
    return name.replace("-", "_").replace(".", "_").lower()

def requirement(name):
    return "@pip_" + _clean_name(name) + "//:pkg"

def whl_requirement(name):
    return "@pip_" + _clean_name(name) + "//:whl"

def data_requirement(name):
    return "@pip_" + _clean_name(name) + "//:data"

def dist_info_requirement(name):
    return "@pip_" + _clean_name(name) + "//:dist_info"

def entry_point(pkg, script = None):
    if not script:
        script = pkg
    return "@pip_" + _clean_name(pkg) + "//:rules_python_wheel_entry_point_" + script

def _get_annotation(requirement):
    # This expects to parse `setuptools==58.2.0     --hash=sha256:2551203ae6955b9876741a26ab3e767bb3242dafe86a32a749ea0d78b6792f11`
    # down wo `setuptools`.
    name = requirement.split(" ")[0].split("=")[0]
    return _annotations.get(name)

def install_deps():
    for name, requirement in _packages:
        maybe(
            whl_library,
            name = name,
            requirement = requirement,
            annotation = _get_annotation(requirement),
            **_config
        )

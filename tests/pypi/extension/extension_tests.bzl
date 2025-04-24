# Copyright 2024 The Bazel Authors. All rights reserved.
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

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:truth.bzl", "subjects")
load("//python/private/pypi:extension.bzl", "parse_modules")  # buildifier: disable=bzl-visibility
load("//python/private/pypi:parse_simpleapi_html.bzl", "parse_simpleapi_html")  # buildifier: disable=bzl-visibility
load("//python/private/pypi:whl_config_setting.bzl", "whl_config_setting")  # buildifier: disable=bzl-visibility

_tests = []

def _mock_mctx(*modules, environ = {}, read = None):
    return struct(
        os = struct(
            environ = environ,
            name = "unittest",
            arch = "exotic",
        ),
        read = read or (lambda _: """\
simple==0.0.1 \
    --hash=sha256:deadbeef \
    --hash=sha256:deadbaaf"""),
        modules = [
            struct(
                name = modules[0].name,
                tags = modules[0].tags,
                is_root = modules[0].is_root,
            ),
        ] + [
            struct(
                name = mod.name,
                tags = mod.tags,
                is_root = False,
            )
            for mod in modules[1:]
        ],
    )

def _mod(*, name, parse = [], override = [], whl_mods = [], is_root = True):
    return struct(
        name = name,
        tags = struct(
            parse = parse,
            override = override,
            whl_mods = whl_mods,
        ),
        is_root = is_root,
    )

def _parse_modules(env, **kwargs):
    return env.expect.that_struct(
        parse_modules(**kwargs),
        attrs = dict(
            exposed_packages = subjects.dict,
            hub_group_map = subjects.dict,
            hub_whl_map = subjects.dict,
            whl_libraries = subjects.dict,
            whl_mods = subjects.dict,
        ),
    )

def _parse(
        *,
        hub_name,
        python_version,
        add_libdir_to_library_search_path = False,
        auth_patterns = {},
        download_only = False,
        enable_implicit_namespace_pkgs = False,
        environment = {},
        envsubst = {},
        experimental_index_url = "",
        experimental_requirement_cycles = {},
        experimental_target_platforms = [],
        extra_hub_aliases = {},
        extra_pip_args = [],
        isolated = True,
        netrc = None,
        parse_all_requirements_files = True,
        pip_data_exclude = None,
        python_interpreter = None,
        python_interpreter_target = None,
        quiet = True,
        requirements_by_platform = {},
        requirements_darwin = None,
        requirements_linux = None,
        requirements_lock = None,
        requirements_windows = None,
        simpleapi_skip = [],
        timeout = 600,
        whl_modifications = {},
        **kwargs):
    return struct(
        auth_patterns = auth_patterns,
        add_libdir_to_library_search_path = add_libdir_to_library_search_path,
        download_only = download_only,
        enable_implicit_namespace_pkgs = enable_implicit_namespace_pkgs,
        environment = environment,
        envsubst = envsubst,
        experimental_index_url = experimental_index_url,
        experimental_requirement_cycles = experimental_requirement_cycles,
        experimental_target_platforms = experimental_target_platforms,
        extra_hub_aliases = extra_hub_aliases,
        extra_pip_args = extra_pip_args,
        hub_name = hub_name,
        isolated = isolated,
        netrc = netrc,
        parse_all_requirements_files = parse_all_requirements_files,
        pip_data_exclude = pip_data_exclude,
        python_interpreter = python_interpreter,
        python_interpreter_target = python_interpreter_target,
        python_version = python_version,
        quiet = quiet,
        requirements_by_platform = requirements_by_platform,
        requirements_darwin = requirements_darwin,
        requirements_linux = requirements_linux,
        requirements_lock = requirements_lock,
        requirements_windows = requirements_windows,
        timeout = timeout,
        whl_modifications = whl_modifications,
        # The following are covered by other unit tests
        experimental_extra_index_urls = [],
        parallel_download = False,
        experimental_index_url_overrides = {},
        simpleapi_skip = simpleapi_skip,
        **kwargs
    )

def _test_simple(env):
    pypi = _parse_modules(
        env,
        module_ctx = _mock_mctx(
            _mod(
                name = "rules_python",
                parse = [
                    _parse(
                        hub_name = "pypi",
                        python_version = "3.15",
                        requirements_lock = "requirements.txt",
                    ),
                ],
            ),
        ),
        available_interpreters = {
            "python_3_15_host": "unit_test_interpreter_target",
        },
        minor_mapping = {"3.15": "3.15.19"},
    )

    pypi.exposed_packages().contains_exactly({"pypi": ["simple"]})
    pypi.hub_group_map().contains_exactly({"pypi": {}})
    pypi.hub_whl_map().contains_exactly({"pypi": {
        "simple": {
            "pypi_315_simple": [
                whl_config_setting(
                    version = "3.15",
                ),
            ],
        },
    }})
    pypi.whl_libraries().contains_exactly({
        "pypi_315_simple": {
            "dep_template": "@pypi//{name}:{target}",
            "python_interpreter_target": "unit_test_interpreter_target",
            "requirement": "simple==0.0.1 --hash=sha256:deadbeef --hash=sha256:deadbaaf",
        },
    })
    pypi.whl_mods().contains_exactly({})

_tests.append(_test_simple)

def _test_simple_multiple_requirements(env):
    pypi = _parse_modules(
        env,
        module_ctx = _mock_mctx(
            _mod(
                name = "rules_python",
                parse = [
                    _parse(
                        hub_name = "pypi",
                        python_version = "3.15",
                        requirements_darwin = "darwin.txt",
                        requirements_windows = "win.txt",
                    ),
                ],
            ),
            read = lambda x: {
                "darwin.txt": "simple==0.0.2 --hash=sha256:deadb00f",
                "win.txt": "simple==0.0.1 --hash=sha256:deadbeef",
            }[x],
        ),
        available_interpreters = {
            "python_3_15_host": "unit_test_interpreter_target",
        },
        minor_mapping = {"3.15": "3.15.19"},
    )

    pypi.exposed_packages().contains_exactly({"pypi": ["simple"]})
    pypi.hub_group_map().contains_exactly({"pypi": {}})
    pypi.hub_whl_map().contains_exactly({"pypi": {
        "simple": {
            "pypi_315_simple_osx_aarch64_osx_x86_64": [
                whl_config_setting(
                    target_platforms = [
                        "cp315_osx_aarch64",
                        "cp315_osx_x86_64",
                    ],
                    version = "3.15",
                ),
            ],
            "pypi_315_simple_windows_x86_64": [
                whl_config_setting(
                    target_platforms = [
                        "cp315_windows_x86_64",
                    ],
                    version = "3.15",
                ),
            ],
        },
    }})
    pypi.whl_libraries().contains_exactly({
        "pypi_315_simple_osx_aarch64_osx_x86_64": {
            "dep_template": "@pypi//{name}:{target}",
            "python_interpreter_target": "unit_test_interpreter_target",
            "requirement": "simple==0.0.2 --hash=sha256:deadb00f",
        },
        "pypi_315_simple_windows_x86_64": {
            "dep_template": "@pypi//{name}:{target}",
            "python_interpreter_target": "unit_test_interpreter_target",
            "requirement": "simple==0.0.1 --hash=sha256:deadbeef",
        },
    })
    pypi.whl_mods().contains_exactly({})

_tests.append(_test_simple_multiple_requirements)

def _test_simple_with_markers(env):
    pypi = _parse_modules(
        env,
        module_ctx = _mock_mctx(
            _mod(
                name = "rules_python",
                parse = [
                    _parse(
                        hub_name = "pypi",
                        python_version = "3.15",
                        requirements_lock = "universal.txt",
                    ),
                ],
            ),
            read = lambda x: {
                "universal.txt": """\
torch==2.4.1+cpu ; platform_machine == 'x86_64'
torch==2.4.1 ; platform_machine != 'x86_64' \
    --hash=sha256:deadbeef
""",
            }[x],
        ),
        available_interpreters = {
            "python_3_15_host": "unit_test_interpreter_target",
        },
        minor_mapping = {"3.15": "3.15.19"},
    )

    pypi.exposed_packages().contains_exactly({"pypi": ["torch"]})
    pypi.hub_group_map().contains_exactly({"pypi": {}})
    pypi.hub_whl_map().contains_exactly({"pypi": {
        "torch": {
            "pypi_315_torch_linux_aarch64_linux_arm_linux_ppc_linux_s390x_osx_aarch64": [
                whl_config_setting(
                    target_platforms = [
                        "cp315_linux_aarch64",
                        "cp315_linux_arm",
                        "cp315_linux_ppc",
                        "cp315_linux_s390x",
                        "cp315_osx_aarch64",
                    ],
                    version = "3.15",
                ),
            ],
            "pypi_315_torch_linux_x86_64_osx_x86_64_windows_x86_64": [
                whl_config_setting(
                    target_platforms = [
                        "cp315_linux_x86_64",
                        "cp315_osx_x86_64",
                        "cp315_windows_x86_64",
                    ],
                    version = "3.15",
                ),
            ],
        },
    }})
    pypi.whl_libraries().contains_exactly({
        "pypi_315_torch_linux_aarch64_linux_arm_linux_ppc_linux_s390x_osx_aarch64": {
            "dep_template": "@pypi//{name}:{target}",
            "python_interpreter_target": "unit_test_interpreter_target",
            "requirement": "torch==2.4.1 --hash=sha256:deadbeef",
        },
        "pypi_315_torch_linux_x86_64_osx_x86_64_windows_x86_64": {
            "dep_template": "@pypi//{name}:{target}",
            "python_interpreter_target": "unit_test_interpreter_target",
            "requirement": "torch==2.4.1+cpu",
        },
    })
    pypi.whl_mods().contains_exactly({})

_tests.append(_test_simple_with_markers)

def _test_torch_experimental_index_url(env):
    def mocksimpleapi_download(*_, **__):
        return {
            "torch": parse_simpleapi_html(
                url = "https://torch.index",
                content = """\
    <a href="/whl/cpu/torch-2.4.1%2Bcpu-cp310-cp310-linux_x86_64.whl#sha256=833490a28ac156762ed6adaa7c695879564fa2fd0dc51bcf3fdb2c7b47dc55e6">torch-2.4.1+cpu-cp310-cp310-linux_x86_64.whl</a><br/>
    <a href="/whl/cpu/torch-2.4.1%2Bcpu-cp310-cp310-win_amd64.whl#sha256=1dd062d296fb78aa7cfab8690bf03704995a821b5ef69cfc807af5c0831b4202">torch-2.4.1+cpu-cp310-cp310-win_amd64.whl</a><br/>
    <a href="/whl/cpu/torch-2.4.1%2Bcpu-cp311-cp311-linux_x86_64.whl#sha256=2b03e20f37557d211d14e3fb3f71709325336402db132a1e0dd8b47392185baf">torch-2.4.1+cpu-cp311-cp311-linux_x86_64.whl</a><br/>
    <a href="/whl/cpu/torch-2.4.1%2Bcpu-cp311-cp311-win_amd64.whl#sha256=76a6fe7b10491b650c630bc9ae328df40f79a948296b41d3b087b29a8a63cbad">torch-2.4.1+cpu-cp311-cp311-win_amd64.whl</a><br/>
    <a href="/whl/cpu/torch-2.4.1%2Bcpu-cp312-cp312-linux_x86_64.whl#sha256=8800deef0026011d502c0c256cc4b67d002347f63c3a38cd8e45f1f445c61364">torch-2.4.1+cpu-cp312-cp312-linux_x86_64.whl</a><br/>
    <a href="/whl/cpu/torch-2.4.1%2Bcpu-cp312-cp312-win_amd64.whl#sha256=3a570e5c553415cdbddfe679207327b3a3806b21c6adea14fba77684d1619e97">torch-2.4.1+cpu-cp312-cp312-win_amd64.whl</a><br/>
    <a href="/whl/cpu/torch-2.4.1%2Bcpu-cp38-cp38-linux_x86_64.whl#sha256=0c0a7cc4f7c74ff024d5a5e21230a01289b65346b27a626f6c815d94b4b8c955">torch-2.4.1+cpu-cp38-cp38-linux_x86_64.whl</a><br/>
    <a href="/whl/cpu/torch-2.4.1%2Bcpu-cp38-cp38-win_amd64.whl#sha256=330e780f478707478f797fdc82c2a96e9b8c5f60b6f1f57bb6ad1dd5b1e7e97e">torch-2.4.1+cpu-cp38-cp38-win_amd64.whl</a><br/>
    <a href="/whl/cpu/torch-2.4.1%2Bcpu-cp39-cp39-linux_x86_64.whl#sha256=3c99506980a2fb4b634008ccb758f42dd82f93ae2830c1e41f64536e310bf562">torch-2.4.1+cpu-cp39-cp39-linux_x86_64.whl</a><br/>
    <a href="/whl/cpu/torch-2.4.1%2Bcpu-cp39-cp39-win_amd64.whl#sha256=c4f2c3c026e876d4dad7629170ec14fff48c076d6c2ae0e354ab3fdc09024f00">torch-2.4.1+cpu-cp39-cp39-win_amd64.whl</a><br/>
    <a href="/whl/cpu/torch-2.4.1-cp310-cp310-manylinux_2_17_aarch64.manylinux2014_aarch64.whl#sha256=fa27b048d32198cda6e9cff0bf768e8683d98743903b7e5d2b1f5098ded1d343">torch-2.4.1-cp310-cp310-manylinux_2_17_aarch64.manylinux2014_aarch64.whl</a><br/>
    <a href="/whl/cpu/torch-2.4.1-cp310-none-macosx_11_0_arm64.whl#sha256=d36a8ef100f5bff3e9c3cea934b9e0d7ea277cb8210c7152d34a9a6c5830eadd">torch-2.4.1-cp310-none-macosx_11_0_arm64.whl</a><br/>
    <a href="/whl/cpu/torch-2.4.1-cp311-cp311-manylinux_2_17_aarch64.manylinux2014_aarch64.whl#sha256=30be2844d0c939161a11073bfbaf645f1c7cb43f62f46cc6e4df1c119fb2a798">torch-2.4.1-cp311-cp311-manylinux_2_17_aarch64.manylinux2014_aarch64.whl</a><br/>
    <a href="/whl/cpu/torch-2.4.1-cp311-none-macosx_11_0_arm64.whl#sha256=ddddbd8b066e743934a4200b3d54267a46db02106876d21cf31f7da7a96f98ea">torch-2.4.1-cp311-none-macosx_11_0_arm64.whl</a><br/>
    <a href="/whl/cpu/torch-2.4.1-cp312-cp312-manylinux_2_17_aarch64.manylinux2014_aarch64.whl#sha256=36109432b10bd7163c9b30ce896f3c2cca1b86b9765f956a1594f0ff43091e2a">torch-2.4.1-cp312-cp312-manylinux_2_17_aarch64.manylinux2014_aarch64.whl</a><br/>
    <a href="/whl/cpu/torch-2.4.1-cp312-none-macosx_11_0_arm64.whl#sha256=72b484d5b6cec1a735bf3fa5a1c4883d01748698c5e9cfdbeb4ffab7c7987e0d">torch-2.4.1-cp312-none-macosx_11_0_arm64.whl</a><br/>
    <a href="/whl/cpu/torch-2.4.1-cp38-cp38-manylinux_2_17_aarch64.manylinux2014_aarch64.whl#sha256=56ad2a760b7a7882725a1eebf5657abbb3b5144eb26bcb47b52059357463c548">torch-2.4.1-cp38-cp38-manylinux_2_17_aarch64.manylinux2014_aarch64.whl</a><br/>
    <a href="/whl/cpu/torch-2.4.1-cp38-none-macosx_11_0_arm64.whl#sha256=5fc1d4d7ed265ef853579caf272686d1ed87cebdcd04f2a498f800ffc53dab71">torch-2.4.1-cp38-none-macosx_11_0_arm64.whl</a><br/>
    <a href="/whl/cpu/torch-2.4.1-cp39-cp39-manylinux_2_17_aarch64.manylinux2014_aarch64.whl#sha256=1495132f30f722af1a091950088baea383fe39903db06b20e6936fd99402803e">torch-2.4.1-cp39-cp39-manylinux_2_17_aarch64.manylinux2014_aarch64.whl</a><br/>
    <a href="/whl/cpu/torch-2.4.1-cp39-none-macosx_11_0_arm64.whl#sha256=a38de2803ee6050309aac032676536c3d3b6a9804248537e38e098d0e14817ec">torch-2.4.1-cp39-none-macosx_11_0_arm64.whl</a><br/>
""",
            ),
        }

    pypi = _parse_modules(
        env,
        module_ctx = _mock_mctx(
            _mod(
                name = "rules_python",
                parse = [
                    _parse(
                        hub_name = "pypi",
                        python_version = "3.12",
                        experimental_index_url = "https://torch.index",
                        requirements_lock = "universal.txt",
                    ),
                ],
            ),
            read = lambda x: {
                "universal.txt": """\
torch==2.4.1 ; platform_machine != 'x86_64' \
    --hash=sha256:1495132f30f722af1a091950088baea383fe39903db06b20e6936fd99402803e \
    --hash=sha256:30be2844d0c939161a11073bfbaf645f1c7cb43f62f46cc6e4df1c119fb2a798 \
    --hash=sha256:36109432b10bd7163c9b30ce896f3c2cca1b86b9765f956a1594f0ff43091e2a \
    --hash=sha256:56ad2a760b7a7882725a1eebf5657abbb3b5144eb26bcb47b52059357463c548 \
    --hash=sha256:5fc1d4d7ed265ef853579caf272686d1ed87cebdcd04f2a498f800ffc53dab71 \
    --hash=sha256:72b484d5b6cec1a735bf3fa5a1c4883d01748698c5e9cfdbeb4ffab7c7987e0d \
    --hash=sha256:a38de2803ee6050309aac032676536c3d3b6a9804248537e38e098d0e14817ec \
    --hash=sha256:d36a8ef100f5bff3e9c3cea934b9e0d7ea277cb8210c7152d34a9a6c5830eadd \
    --hash=sha256:ddddbd8b066e743934a4200b3d54267a46db02106876d21cf31f7da7a96f98ea \
    --hash=sha256:fa27b048d32198cda6e9cff0bf768e8683d98743903b7e5d2b1f5098ded1d343
    # via -r requirements.in
torch==2.4.1+cpu ; platform_machine == 'x86_64' \
    --hash=sha256:0c0a7cc4f7c74ff024d5a5e21230a01289b65346b27a626f6c815d94b4b8c955 \
    --hash=sha256:1dd062d296fb78aa7cfab8690bf03704995a821b5ef69cfc807af5c0831b4202 \
    --hash=sha256:2b03e20f37557d211d14e3fb3f71709325336402db132a1e0dd8b47392185baf \
    --hash=sha256:330e780f478707478f797fdc82c2a96e9b8c5f60b6f1f57bb6ad1dd5b1e7e97e \
    --hash=sha256:3a570e5c553415cdbddfe679207327b3a3806b21c6adea14fba77684d1619e97 \
    --hash=sha256:3c99506980a2fb4b634008ccb758f42dd82f93ae2830c1e41f64536e310bf562 \
    --hash=sha256:76a6fe7b10491b650c630bc9ae328df40f79a948296b41d3b087b29a8a63cbad \
    --hash=sha256:833490a28ac156762ed6adaa7c695879564fa2fd0dc51bcf3fdb2c7b47dc55e6 \
    --hash=sha256:8800deef0026011d502c0c256cc4b67d002347f63c3a38cd8e45f1f445c61364 \
    --hash=sha256:c4f2c3c026e876d4dad7629170ec14fff48c076d6c2ae0e354ab3fdc09024f00
    # via -r requirements.in
""",
            }[x],
        ),
        available_interpreters = {
            "python_3_12_host": "unit_test_interpreter_target",
        },
        minor_mapping = {"3.12": "3.12.19"},
        simpleapi_download = mocksimpleapi_download,
    )

    pypi.exposed_packages().contains_exactly({"pypi": ["torch"]})
    pypi.hub_group_map().contains_exactly({"pypi": {}})
    pypi.hub_whl_map().contains_exactly({"pypi": {
        "torch": {
            "pypi_312_torch_cp312_cp312_linux_x86_64_8800deef": [
                struct(
                    config_setting = None,
                    filename = "torch-2.4.1+cpu-cp312-cp312-linux_x86_64.whl",
                    target_platforms = None,
                    version = "3.12",
                ),
            ],
            "pypi_312_torch_cp312_cp312_manylinux_2_17_aarch64_36109432": [
                struct(
                    config_setting = None,
                    filename = "torch-2.4.1-cp312-cp312-manylinux_2_17_aarch64.manylinux2014_aarch64.whl",
                    target_platforms = None,
                    version = "3.12",
                ),
            ],
            "pypi_312_torch_cp312_cp312_win_amd64_3a570e5c": [
                struct(
                    config_setting = None,
                    filename = "torch-2.4.1+cpu-cp312-cp312-win_amd64.whl",
                    target_platforms = None,
                    version = "3.12",
                ),
            ],
            "pypi_312_torch_cp312_none_macosx_11_0_arm64_72b484d5": [
                struct(
                    config_setting = None,
                    filename = "torch-2.4.1-cp312-none-macosx_11_0_arm64.whl",
                    target_platforms = None,
                    version = "3.12",
                ),
            ],
        },
    }})
    pypi.whl_libraries().contains_exactly({
        "pypi_312_torch_cp312_cp312_linux_x86_64_8800deef": {
            "dep_template": "@pypi//{name}:{target}",
            "filename": "torch-2.4.1+cpu-cp312-cp312-linux_x86_64.whl",
            "python_interpreter_target": "unit_test_interpreter_target",
            "requirement": "torch==2.4.1+cpu",
            "sha256": "8800deef0026011d502c0c256cc4b67d002347f63c3a38cd8e45f1f445c61364",
            "urls": ["https://torch.index/whl/cpu/torch-2.4.1%2Bcpu-cp312-cp312-linux_x86_64.whl"],
        },
        "pypi_312_torch_cp312_cp312_manylinux_2_17_aarch64_36109432": {
            "dep_template": "@pypi//{name}:{target}",
            "filename": "torch-2.4.1-cp312-cp312-manylinux_2_17_aarch64.manylinux2014_aarch64.whl",
            "python_interpreter_target": "unit_test_interpreter_target",
            "requirement": "torch==2.4.1",
            "sha256": "36109432b10bd7163c9b30ce896f3c2cca1b86b9765f956a1594f0ff43091e2a",
            "urls": ["https://torch.index/whl/cpu/torch-2.4.1-cp312-cp312-manylinux_2_17_aarch64.manylinux2014_aarch64.whl"],
        },
        "pypi_312_torch_cp312_cp312_win_amd64_3a570e5c": {
            "dep_template": "@pypi//{name}:{target}",
            "filename": "torch-2.4.1+cpu-cp312-cp312-win_amd64.whl",
            "python_interpreter_target": "unit_test_interpreter_target",
            "requirement": "torch==2.4.1+cpu",
            "sha256": "3a570e5c553415cdbddfe679207327b3a3806b21c6adea14fba77684d1619e97",
            "urls": ["https://torch.index/whl/cpu/torch-2.4.1%2Bcpu-cp312-cp312-win_amd64.whl"],
        },
        "pypi_312_torch_cp312_none_macosx_11_0_arm64_72b484d5": {
            "dep_template": "@pypi//{name}:{target}",
            "filename": "torch-2.4.1-cp312-none-macosx_11_0_arm64.whl",
            "python_interpreter_target": "unit_test_interpreter_target",
            "requirement": "torch==2.4.1",
            "sha256": "72b484d5b6cec1a735bf3fa5a1c4883d01748698c5e9cfdbeb4ffab7c7987e0d",
            "urls": ["https://torch.index/whl/cpu/torch-2.4.1-cp312-none-macosx_11_0_arm64.whl"],
        },
    })
    pypi.whl_mods().contains_exactly({})

_tests.append(_test_torch_experimental_index_url)

def _test_download_only_multiple(env):
    pypi = _parse_modules(
        env,
        module_ctx = _mock_mctx(
            _mod(
                name = "rules_python",
                parse = [
                    _parse(
                        hub_name = "pypi",
                        python_version = "3.15",
                        download_only = True,
                        requirements_by_platform = {
                            "requirements.linux_x86_64.txt": "linux_x86_64",
                            "requirements.osx_aarch64.txt": "osx_aarch64",
                        },
                    ),
                ],
            ),
            read = lambda x: {
                "requirements.linux_x86_64.txt": """\
--platform=manylinux_2_17_x86_64
--python-version=315
--implementation=cp
--abi=cp315

simple==0.0.1 \
    --hash=sha256:deadbeef
extra==0.0.1 \
    --hash=sha256:deadb00f
""",
                "requirements.osx_aarch64.txt": """\
--platform=macosx_10_9_arm64
--python-version=315
--implementation=cp
--abi=cp315

simple==0.0.3 \
    --hash=sha256:deadbaaf
""",
            }[x],
        ),
        available_interpreters = {
            "python_3_15_host": "unit_test_interpreter_target",
        },
        minor_mapping = {"3.15": "3.15.19"},
    )

    pypi.exposed_packages().contains_exactly({"pypi": ["simple"]})
    pypi.hub_group_map().contains_exactly({"pypi": {}})
    pypi.hub_whl_map().contains_exactly({"pypi": {
        "extra": {
            "pypi_315_extra": [
                whl_config_setting(version = "3.15"),
            ],
        },
        "simple": {
            "pypi_315_simple_linux_x86_64": [
                whl_config_setting(
                    target_platforms = ["cp315_linux_x86_64"],
                    version = "3.15",
                ),
            ],
            "pypi_315_simple_osx_aarch64": [
                whl_config_setting(
                    target_platforms = ["cp315_osx_aarch64"],
                    version = "3.15",
                ),
            ],
        },
    }})
    pypi.whl_libraries().contains_exactly({
        "pypi_315_extra": {
            "dep_template": "@pypi//{name}:{target}",
            "download_only": True,
            # TODO @aignas 2025-04-20: ensure that this is in the hub repo
            # "experimental_target_platforms": ["cp315_linux_x86_64"],
            "extra_pip_args": ["--platform=manylinux_2_17_x86_64", "--python-version=315", "--implementation=cp", "--abi=cp315"],
            "python_interpreter_target": "unit_test_interpreter_target",
            "requirement": "extra==0.0.1 --hash=sha256:deadb00f",
        },
        "pypi_315_simple_linux_x86_64": {
            "dep_template": "@pypi//{name}:{target}",
            "download_only": True,
            "extra_pip_args": ["--platform=manylinux_2_17_x86_64", "--python-version=315", "--implementation=cp", "--abi=cp315"],
            "python_interpreter_target": "unit_test_interpreter_target",
            "requirement": "simple==0.0.1 --hash=sha256:deadbeef",
        },
        "pypi_315_simple_osx_aarch64": {
            "dep_template": "@pypi//{name}:{target}",
            "download_only": True,
            "extra_pip_args": ["--platform=macosx_10_9_arm64", "--python-version=315", "--implementation=cp", "--abi=cp315"],
            "python_interpreter_target": "unit_test_interpreter_target",
            "requirement": "simple==0.0.3 --hash=sha256:deadbaaf",
        },
    })
    pypi.whl_mods().contains_exactly({})

_tests.append(_test_download_only_multiple)

def _test_simple_get_index(env):
    got_simpleapi_download_args = []
    got_simpleapi_download_kwargs = {}

    def mocksimpleapi_download(*args, **kwargs):
        got_simpleapi_download_args.extend(args)
        got_simpleapi_download_kwargs.update(kwargs)
        return {
            "simple": struct(
                whls = {
                    "deadb00f": struct(
                        yanked = False,
                        filename = "simple-0.0.1-py3-none-any.whl",
                        sha256 = "deadb00f",
                        url = "example2.org",
                    ),
                },
                sdists = {
                    "deadbeef": struct(
                        yanked = False,
                        filename = "simple-0.0.1.tar.gz",
                        sha256 = "deadbeef",
                        url = "example.org",
                    ),
                },
            ),
            "some_other_pkg": struct(
                whls = {
                    "deadb33f": struct(
                        yanked = False,
                        filename = "some-other-pkg-0.0.1-py3-none-any.whl",
                        sha256 = "deadb33f",
                        url = "example2.org/index/some_other_pkg/",
                    ),
                },
                sdists = {},
                sha256s_by_version = {
                    "0.0.1": ["deadb33f"],
                    "0.0.3": ["deadbeef"],
                },
            ),
        }

    pypi = _parse_modules(
        env,
        module_ctx = _mock_mctx(
            _mod(
                name = "rules_python",
                parse = [
                    _parse(
                        hub_name = "pypi",
                        python_version = "3.15",
                        requirements_lock = "requirements.txt",
                        experimental_index_url = "pypi.org",
                        extra_pip_args = [
                            "--extra-args-for-sdist-building",
                        ],
                    ),
                ],
            ),
            read = lambda x: {
                "requirements.txt": """
simple==0.0.1 \
    --hash=sha256:deadbeef \
    --hash=sha256:deadb00f
some_pkg==0.0.1 @ example-direct.org/some_pkg-0.0.1-py3-none-any.whl \
    --hash=sha256:deadbaaf
direct_without_sha==0.0.1 @ example-direct.org/direct_without_sha-0.0.1-py3-none-any.whl
some_other_pkg==0.0.1
pip_fallback==0.0.1
direct_sdist_without_sha @ some-archive/any-name.tar.gz
git_dep @ git+https://git.server/repo/project@deadbeefdeadbeef
""",
            }[x],
        ),
        available_interpreters = {
            "python_3_15_host": "unit_test_interpreter_target",
        },
        minor_mapping = {"3.15": "3.15.19"},
        simpleapi_download = mocksimpleapi_download,
    )

    pypi.exposed_packages().contains_exactly({"pypi": [
        "direct_sdist_without_sha",
        "direct_without_sha",
        "git_dep",
        "pip_fallback",
        "simple",
        "some_other_pkg",
        "some_pkg",
    ]})
    pypi.hub_group_map().contains_exactly({"pypi": {}})
    pypi.hub_whl_map().contains_exactly({
        "pypi": {
            "direct_sdist_without_sha": {
                "pypi_315_any_name": [
                    struct(
                        config_setting = None,
                        filename = "any-name.tar.gz",
                        target_platforms = None,
                        version = "3.15",
                    ),
                ],
            },
            "direct_without_sha": {
                "pypi_315_direct_without_sha_0_0_1_py3_none_any": [
                    struct(
                        config_setting = None,
                        filename = "direct_without_sha-0.0.1-py3-none-any.whl",
                        target_platforms = None,
                        version = "3.15",
                    ),
                ],
            },
            "git_dep": {
                "pypi_315_git_dep": [
                    struct(
                        config_setting = None,
                        filename = None,
                        target_platforms = None,
                        version = "3.15",
                    ),
                ],
            },
            "pip_fallback": {
                "pypi_315_pip_fallback": [
                    struct(
                        config_setting = None,
                        filename = None,
                        target_platforms = None,
                        version = "3.15",
                    ),
                ],
            },
            "simple": {
                "pypi_315_simple_py3_none_any_deadb00f": [
                    struct(
                        config_setting = None,
                        filename = "simple-0.0.1-py3-none-any.whl",
                        target_platforms = None,
                        version = "3.15",
                    ),
                ],
                "pypi_315_simple_sdist_deadbeef": [
                    struct(
                        config_setting = None,
                        filename = "simple-0.0.1.tar.gz",
                        target_platforms = None,
                        version = "3.15",
                    ),
                ],
            },
            "some_other_pkg": {
                "pypi_315_some_py3_none_any_deadb33f": [
                    struct(
                        config_setting = None,
                        filename = "some-other-pkg-0.0.1-py3-none-any.whl",
                        target_platforms = None,
                        version = "3.15",
                    ),
                ],
            },
            "some_pkg": {
                "pypi_315_some_pkg_py3_none_any_deadbaaf": [
                    struct(
                        config_setting = None,
                        filename = "some_pkg-0.0.1-py3-none-any.whl",
                        target_platforms = None,
                        version = "3.15",
                    ),
                ],
            },
        },
    })
    pypi.whl_libraries().contains_exactly({
        "pypi_315_any_name": {
            "dep_template": "@pypi//{name}:{target}",
            "extra_pip_args": ["--extra-args-for-sdist-building"],
            "filename": "any-name.tar.gz",
            "python_interpreter_target": "unit_test_interpreter_target",
            "requirement": "direct_sdist_without_sha @ some-archive/any-name.tar.gz",
            "sha256": "",
            "urls": ["some-archive/any-name.tar.gz"],
        },
        "pypi_315_direct_without_sha_0_0_1_py3_none_any": {
            "dep_template": "@pypi//{name}:{target}",
            "filename": "direct_without_sha-0.0.1-py3-none-any.whl",
            "python_interpreter_target": "unit_test_interpreter_target",
            "requirement": "direct_without_sha==0.0.1 @ example-direct.org/direct_without_sha-0.0.1-py3-none-any.whl",
            "sha256": "",
            "urls": ["example-direct.org/direct_without_sha-0.0.1-py3-none-any.whl"],
        },
        "pypi_315_git_dep": {
            "dep_template": "@pypi//{name}:{target}",
            "extra_pip_args": ["--extra-args-for-sdist-building"],
            "python_interpreter_target": "unit_test_interpreter_target",
            "requirement": "git_dep @ git+https://git.server/repo/project@deadbeefdeadbeef",
        },
        "pypi_315_pip_fallback": {
            "dep_template": "@pypi//{name}:{target}",
            "extra_pip_args": ["--extra-args-for-sdist-building"],
            "python_interpreter_target": "unit_test_interpreter_target",
            "requirement": "pip_fallback==0.0.1",
        },
        "pypi_315_simple_py3_none_any_deadb00f": {
            "dep_template": "@pypi//{name}:{target}",
            "filename": "simple-0.0.1-py3-none-any.whl",
            "python_interpreter_target": "unit_test_interpreter_target",
            "requirement": "simple==0.0.1",
            "sha256": "deadb00f",
            "urls": ["example2.org"],
        },
        "pypi_315_simple_sdist_deadbeef": {
            "dep_template": "@pypi//{name}:{target}",
            "extra_pip_args": ["--extra-args-for-sdist-building"],
            "filename": "simple-0.0.1.tar.gz",
            "python_interpreter_target": "unit_test_interpreter_target",
            "requirement": "simple==0.0.1",
            "sha256": "deadbeef",
            "urls": ["example.org"],
        },
        "pypi_315_some_pkg_py3_none_any_deadbaaf": {
            "dep_template": "@pypi//{name}:{target}",
            "filename": "some_pkg-0.0.1-py3-none-any.whl",
            "python_interpreter_target": "unit_test_interpreter_target",
            "requirement": "some_pkg==0.0.1 @ example-direct.org/some_pkg-0.0.1-py3-none-any.whl --hash=sha256:deadbaaf",
            "sha256": "deadbaaf",
            "urls": ["example-direct.org/some_pkg-0.0.1-py3-none-any.whl"],
        },
        "pypi_315_some_py3_none_any_deadb33f": {
            "dep_template": "@pypi//{name}:{target}",
            "filename": "some-other-pkg-0.0.1-py3-none-any.whl",
            "python_interpreter_target": "unit_test_interpreter_target",
            "requirement": "some_other_pkg==0.0.1",
            "sha256": "deadb33f",
            "urls": ["example2.org/index/some_other_pkg/"],
        },
    })
    pypi.whl_mods().contains_exactly({})
    env.expect.that_dict(got_simpleapi_download_kwargs).contains_exactly(
        {
            "attr": struct(
                auth_patterns = {},
                envsubst = {},
                extra_index_urls = [],
                index_url = "pypi.org",
                index_url_overrides = {},
                netrc = None,
                sources = ["simple", "pip_fallback", "some_other_pkg"],
            ),
            "cache": {},
            "parallel_download": False,
        },
    )

_tests.append(_test_simple_get_index)

def _test_optimum_sys_platform_extra(env):
    pypi = _parse_modules(
        env,
        module_ctx = _mock_mctx(
            _mod(
                name = "rules_python",
                parse = [
                    _parse(
                        hub_name = "pypi",
                        python_version = "3.15",
                        requirements_lock = "universal.txt",
                    ),
                ],
            ),
            read = lambda x: {
                "universal.txt": """\
optimum[onnxruntime]==1.17.1 ; sys_platform == 'darwin'
optimum[onnxruntime-gpu]==1.17.1 ; sys_platform == 'linux'
""",
            }[x],
        ),
        available_interpreters = {
            "python_3_15_host": "unit_test_interpreter_target",
        },
        minor_mapping = {"3.15": "3.15.19"},
    )

    pypi.exposed_packages().contains_exactly({"pypi": []})
    pypi.hub_group_map().contains_exactly({"pypi": {}})
    pypi.hub_whl_map().contains_exactly({
        "pypi": {
            "optimum": {
                "pypi_315_optimum_linux_aarch64_linux_arm_linux_ppc_linux_s390x_linux_x86_64": [
                    whl_config_setting(
                        version = "3.15",
                        target_platforms = [
                            "cp315_linux_aarch64",
                            "cp315_linux_arm",
                            "cp315_linux_ppc",
                            "cp315_linux_s390x",
                            "cp315_linux_x86_64",
                        ],
                        config_setting = None,
                        filename = None,
                    ),
                ],
                "pypi_315_optimum_osx_aarch64_osx_x86_64": [
                    whl_config_setting(
                        version = "3.15",
                        target_platforms = [
                            "cp315_osx_aarch64",
                            "cp315_osx_x86_64",
                        ],
                        config_setting = None,
                        filename = None,
                    ),
                ],
            },
        },
    })

    pypi.whl_libraries().contains_exactly({
        "pypi_315_optimum_linux_aarch64_linux_arm_linux_ppc_linux_s390x_linux_x86_64": {
            "dep_template": "@pypi//{name}:{target}",
            "python_interpreter_target": "unit_test_interpreter_target",
            "requirement": "optimum[onnxruntime-gpu]==1.17.1",
        },
        "pypi_315_optimum_osx_aarch64_osx_x86_64": {
            "dep_template": "@pypi//{name}:{target}",
            "python_interpreter_target": "unit_test_interpreter_target",
            "requirement": "optimum[onnxruntime]==1.17.1",
        },
    })
    pypi.whl_mods().contains_exactly({})

_tests.append(_test_optimum_sys_platform_extra)

def extension_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)

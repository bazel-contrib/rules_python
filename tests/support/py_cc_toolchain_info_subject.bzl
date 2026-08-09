# Copyright 2023 The Bazel Authors. All rights reserved.
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
"""PyCcToolchainInfo testing subject."""

load("@rules_testing//lib:truth.bzl", "subjects")

def _py_cc_toolchain_info_subject_new(info, *, meta):
    # buildifier: disable=uninitialized
    public = struct(
        abi_flags = lambda *a, **k: _py_cc_toolchain_info_subject_abi_flags(self, *a, **k),
        headers = lambda *a, **k: _py_cc_toolchain_info_subject_headers(self, *a, **k),
        headers_abi3 = lambda *a, **k: _py_cc_toolchain_info_subject_headers_abi3(self, *a, **k),
        libs = lambda *a, **k: _py_cc_toolchain_info_subject_libs(self, *a, **k),
        platform_machine = lambda *a, **k: _py_cc_toolchain_info_subject_platform_machine(self, *a, **k),
        platform_tag = lambda *a, **k: _py_cc_toolchain_info_subject_platform_tag(self, *a, **k),
        python_version = lambda *a, **k: _py_cc_toolchain_info_subject_python_version(self, *a, **k),
        soabi = lambda *a, **k: _py_cc_toolchain_info_subject_soabi(self, *a, **k),
        sys_platform = lambda *a, **k: _py_cc_toolchain_info_subject_sys_platform(self, *a, **k),
        actual = info,
    )
    self = struct(actual = info, meta = meta)
    return public

def _py_cc_toolchain_info_subject_abi_flags(self):
    return subjects.str(
        self.actual.abi_flags,
        meta = self.meta.derive("abi_flags()"),
    )

def _py_cc_toolchain_info_subject_headers(self):
    return subjects.struct(
        self.actual.headers,
        meta = self.meta.derive("headers()"),
        attrs = dict(
            providers_map = subjects.dict,
        ),
    )

def _py_cc_toolchain_info_subject_headers_abi3(self):
    return subjects.struct(
        self.actual.headers_abi3,
        meta = self.meta.derive("headers_abi3()"),
        attrs = dict(
            providers_map = subjects.dict,
        ),
    )

def _py_cc_toolchain_info_subject_libs(self):
    return subjects.struct(
        self.actual.libs,
        meta = self.meta.derive("libs()"),
        attrs = dict(
            providers_map = subjects.dict,
        ),
    )

def _py_cc_toolchain_info_subject_platform_machine(self):
    return subjects.str(
        self.actual.platform_machine,
        meta = self.meta.derive("platform_machine()"),
    )

def _py_cc_toolchain_info_subject_platform_tag(self):
    return subjects.str(
        self.actual.platform_tag,
        meta = self.meta.derive("platform_tag()"),
    )

def _py_cc_toolchain_info_subject_python_version(self):
    return subjects.str(
        self.actual.python_version,
        meta = self.meta.derive("python_version()"),
    )

def _py_cc_toolchain_info_subject_soabi(self):
    return subjects.str(
        self.actual.soabi,
        meta = self.meta.derive("soabi()"),
    )

def _py_cc_toolchain_info_subject_sys_platform(self):
    return subjects.str(
        self.actual.sys_platform,
        meta = self.meta.derive("sys_platform()"),
    )

# Disable this to aid doc generation
# buildifier: disable=name-conventions
PyCcToolchainInfoSubject = struct(
    new = _py_cc_toolchain_info_subject_new,
)

# Copyright 2025 The Bazel Authors. All rights reserved.
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

"""Parity tests comparing cc_shared_library and py_extension behavior."""

load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc:cc_shared_library.bzl", "cc_shared_library")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")
load("//python/cc:py_extension.bzl", "py_extension")
# buildifier: disable=bzl-visibility
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

# Test 1: CSL A -> CSL B -> CSL C (Dynamic deps)
def _test_csl_dynamic_deps(name):
    util.helper_target(
        cc_library,
        name = name + "_libC",
        srcs = ["test_lib_c.c"],
        hdrs = ["test_symbols.h"],
        copts = ["-fPIC"],
    )
    util.helper_target(
        cc_shared_library,
        name = name + "_cslC",
        deps = [":" + name + "_libC"],
    )
    util.helper_target(
        cc_library,
        name = name + "_libB",
        srcs = ["test_lib_b.c"],
        hdrs = ["test_symbols.h"],
        copts = ["-fPIC"],
        deps = [":" + name + "_libC"],
    )
    util.helper_target(
        cc_shared_library,
        name = name + "_cslB",
        deps = [":" + name + "_libB"],
        dynamic_deps = [":" + name + "_cslC"],
    )
    util.helper_target(
        cc_library,
        name = name + "_libA",
        srcs = ["test_lib_a.c"],
        hdrs = ["test_symbols.h"],
        copts = ["-fPIC"],
        deps = [":" + name + "_libB", ":" + name + "_libC"],
    )
    util.helper_target(
        cc_shared_library,
        name = name + "_cslA",
        deps = [":" + name + "_libA"],
        dynamic_deps = [":" + name + "_cslB", ":" + name + "_cslC"],
    )
    analysis_test(
        name = name,
        target = name + "_cslA",
        impl = _csl_dynamic_deps_test_impl,
    )

def _csl_dynamic_deps_test_impl(env, target):
    env.expect.that_target(target).has_provider(CcSharedLibraryInfo)

# Test 2: py_extension A -> CSL B -> CSL C (Dynamic deps)
def _test_pyext_dynamic_deps(name):
    util.helper_target(
        cc_library,
        name = name + "_libC",
        srcs = ["test_lib_c.c"],
        hdrs = ["test_symbols.h"],
        copts = ["-fPIC"],
    )
    util.helper_target(
        cc_shared_library,
        name = name + "_cslC",
        deps = [":" + name + "_libC"],
    )
    util.helper_target(
        cc_library,
        name = name + "_libB",
        srcs = ["test_lib_b.c"],
        hdrs = ["test_symbols.h"],
        copts = ["-fPIC"],
        deps = [":" + name + "_libC"],
    )
    util.helper_target(
        cc_shared_library,
        name = name + "_cslB",
        deps = [":" + name + "_libB"],
        dynamic_deps = [":" + name + "_cslC"],
    )
    util.helper_target(
        cc_library,
        name = name + "_libA",
        srcs = ["test_lib_a.c"],
        hdrs = ["test_symbols.h"],
        copts = ["-fPIC"],
        deps = [":" + name + "_libB", ":" + name + "_libC"],
    )
    py_extension(
        name = name + "_pyextA",
        static_deps = [":" + name + "_libA"],
        dynamic_deps = [":" + name + "_cslB", ":" + name + "_cslC"],
    )
    analysis_test(
        name = name,
        target = name + "_pyextA",
        impl = _pyext_dynamic_deps_test_impl,
    )

def _pyext_dynamic_deps_test_impl(env, target):
    env.expect.that_target(target).has_provider(CcInfo)
    cc_info = target[CcInfo]
    # Should propagate CcInfo from dynamic_deps (cslB and cslC)
    env.expect.that_collection(cc_info.linking_context.linker_inputs.to_list()).has_size(2)

# Test 3: CSL A -> CSL B, CL C (Static sharing)
def _test_csl_static_sharing(name):
    util.helper_target(
        cc_library,
        name = name + "_libC",
        srcs = ["test_lib_c.c"],
        hdrs = ["test_symbols.h"],
        copts = ["-fPIC"],
    )
    util.helper_target(
        cc_library,
        name = name + "_libB",
        srcs = ["test_lib_b.c"],
        hdrs = ["test_symbols.h"],
        copts = ["-fPIC"],
        deps = [":" + name + "_libC"],
    )
    util.helper_target(
        cc_shared_library,
        name = name + "_cslB",
        deps = [":" + name + "_libB", ":" + name + "_libC"],
    )
    util.helper_target(
        cc_library,
        name = name + "_libA",
        srcs = ["test_lib_a.c"],
        hdrs = ["test_symbols.h"],
        copts = ["-fPIC"],
        deps = [":" + name + "_libB", ":" + name + "_libC"],
    )
    util.helper_target(
        cc_shared_library,
        name = name + "_cslA",
        deps = [":" + name + "_libA"],
        dynamic_deps = [":" + name + "_cslB"],
    )
    analysis_test(
        name = name,
        target = name + "_cslA",
        impl = _csl_static_sharing_test_impl,
    )

def _csl_static_sharing_test_impl(env, target):
    env.expect.that_target(target).has_provider(CcSharedLibraryInfo)

# Test 4: Same as 3, but A is py_extension
def _test_pyext_static_sharing(name):
    util.helper_target(
        cc_library,
        name = name + "_libC",
        srcs = ["test_lib_c.c"],
        hdrs = ["test_symbols.h"],
        copts = ["-fPIC"],
    )
    util.helper_target(
        cc_library,
        name = name + "_libB",
        srcs = ["test_lib_b.c"],
        hdrs = ["test_symbols.h"],
        copts = ["-fPIC"],
        deps = [":" + name + "_libC"],
    )
    util.helper_target(
        cc_shared_library,
        name = name + "_cslB",
        deps = [":" + name + "_libB", ":" + name + "_libC"],
    )
    util.helper_target(
        cc_library,
        name = name + "_libA",
        srcs = ["test_lib_a.c"],
        hdrs = ["test_symbols.h"],
        copts = ["-fPIC"],
        deps = [":" + name + "_libB", ":" + name + "_libC"],
    )
    py_extension(
        name = name + "_pyextA",
        static_deps = [":" + name + "_libA", ":" + name + "_libC"],
        dynamic_deps = [":" + name + "_cslB"],
    )
    analysis_test(
        name = name,
        target = name + "_pyextA",
        impl = _pyext_static_sharing_test_impl,
    )

def _pyext_static_sharing_test_impl(env, target):
    env.expect.that_target(target).has_provider(CcInfo)

def dependency_graph_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_csl_dynamic_deps,
            _test_pyext_dynamic_deps,
            _test_csl_static_sharing,
            _test_pyext_static_sharing,
        ],
    )

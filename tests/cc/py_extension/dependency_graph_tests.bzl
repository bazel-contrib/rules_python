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
load("@rules_cc//cc/common:cc_shared_library_info.bzl", "CcSharedLibraryInfo")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")
load("//python/cc:py_extension.bzl", "py_extension")

# For tests 1 and 2
def _create_dynamic_deps_helpers(name):
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

# Test 1: CSL A -> CSL B -> CSL C (Dynamic deps)
def _test_csl_dynamic_deps_top(name):
    _create_dynamic_deps_helpers(name)
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
    csl_info = target[CcSharedLibraryInfo]

    # Derive labels
    test_name = target.label.name[:-5]  # remove "_cslA"
    libA_label = target.label.same_package_label(test_name + "_libA")
    libB_label = target.label.same_package_label(test_name + "_libB")
    libC_label = target.label.same_package_label(test_name + "_libC")

    env.expect.that_collection([str(e) for e in csl_info.exports]).contains_exactly([str(libA_label)])
    if hasattr(csl_info, "link_once_static_libs"):
        static_libs = [str(l) for l in csl_info.link_once_static_libs]
        env.expect.that_collection(static_libs).contains(str(libA_label))
        env.expect.that_collection(static_libs).contains_none_of([str(libB_label), str(libC_label)])

# Test 2: py_extension A -> CSL B -> CSL C (Dynamic deps)
def _test_pyext_dynamic_deps_top(name):
    _create_dynamic_deps_helpers(name)
    py_extension(
        name = name + "_pyextA",
        deps = [":" + name + "_libA"],
        dynamic_deps = [":" + name + "_cslB", ":" + name + "_cslC"],
    )
    analysis_test(
        name = name,
        target = name + "_pyextA",
        impl = _pyext_dynamic_deps_test_impl,
    )

def _test_pyext_dynamic_deps_cslB(name):
    _create_dynamic_deps_helpers(name)
    analysis_test(
        name = name,
        target = name + "_cslB",
        impl = _cslB_deps_test_impl,
    )

def _test_pyext_dynamic_deps_cslC(name):
    _create_dynamic_deps_helpers(name)
    analysis_test(
        name = name,
        target = name + "_cslC",
        impl = _cslC_deps_test_impl,
    )

def _cslC_deps_test_impl(env, target):
    env.expect.that_target(target).has_provider(CcSharedLibraryInfo)
    csl_info = target[CcSharedLibraryInfo]

    # Derive labels
    test_name = target.label.name[:-5]  # remove "_cslC"
    libC_label = target.label.same_package_label(test_name + "_libC")

    env.expect.that_collection([str(e) for e in csl_info.exports]).contains_exactly([str(libC_label)])
    if hasattr(csl_info, "link_once_static_libs"):
        env.expect.that_collection([str(l) for l in csl_info.link_once_static_libs]).contains_exactly([str(libC_label)])

def _cslB_deps_test_impl(env, target):
    env.expect.that_target(target).has_provider(CcSharedLibraryInfo)
    csl_info = target[CcSharedLibraryInfo]

    # Derive labels
    test_name = target.label.name[:-5]  # remove "_cslB"
    libB_label = target.label.same_package_label(test_name + "_libB")
    libC_label = target.label.same_package_label(test_name + "_libC")
    cslC_label = target.label.same_package_label(test_name + "_cslC")

    env.expect.that_collection([str(e) for e in csl_info.exports]).contains_exactly([str(libB_label)])
    if hasattr(csl_info, "link_once_static_libs"):
        static_libs = [str(l) for l in csl_info.link_once_static_libs]
        env.expect.that_collection(static_libs).contains(str(libB_label))
        env.expect.that_collection(static_libs).contains_none_of([str(libC_label)])

    if hasattr(csl_info, "dynamic_deps"):
        dynamic_deps = [str(d.linker_input.owner) for d in csl_info.dynamic_deps.to_list()]
        env.expect.that_collection(dynamic_deps).contains(str(cslC_label))

def _pyext_dynamic_deps_test_impl(env, target):
    env.expect.that_target(target).has_provider(CcSharedLibraryInfo)
    csl_info = target[CcSharedLibraryInfo]

    # Derive labels
    test_name = target.label.name[:-7]  # remove "_pyextA"
    libA_label = target.label.same_package_label(test_name + "_libA")
    libB_label = target.label.same_package_label(test_name + "_libB")
    libC_label = target.label.same_package_label(test_name + "_libC")

    env.expect.that_collection([str(e) for e in csl_info.exports]).contains_exactly([str(libA_label)])
    if hasattr(csl_info, "link_once_static_libs"):
        static_libs = [str(l) for l in csl_info.link_once_static_libs]
        env.expect.that_collection(static_libs).contains(str(libA_label))
        env.expect.that_collection(static_libs).contains_none_of([str(libB_label), str(libC_label)])

# For tests 3 and 4
def _create_static_sharing_helpers(name):
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

# Test 3: CSL A -> CSL B, CL C (Static sharing)
def _test_csl_static_sharing_top(name):
    _create_static_sharing_helpers(name)
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
    csl_info = target[CcSharedLibraryInfo]

    # Derive labels
    test_name = target.label.name[:-5]  # remove "_cslA"
    libA_label = target.label.same_package_label(test_name + "_libA")
    libB_label = target.label.same_package_label(test_name + "_libB")
    libC_label = target.label.same_package_label(test_name + "_libC")

    env.expect.that_collection([str(e) for e in csl_info.exports]).contains_exactly([str(libA_label)])
    if hasattr(csl_info, "link_once_static_libs"):
        static_libs = [str(l) for l in csl_info.link_once_static_libs]
        env.expect.that_collection(static_libs).contains(str(libA_label))
        env.expect.that_collection(static_libs).contains_none_of([str(libB_label), str(libC_label)])

# Test 4: Same as 3, but A is py_extension
def _test_pyext_static_sharing_top(name):
    _create_static_sharing_helpers(name)
    py_extension(
        name = name + "_pyextA",
        deps = [":" + name + "_libA"],
        dynamic_deps = [":" + name + "_cslB"],
    )
    analysis_test(
        name = name,
        target = name + "_pyextA",
        impl = _pyext_static_sharing_test_impl,
    )

def _test_pyext_static_sharing_cslB(name):
    _create_static_sharing_helpers(name)
    analysis_test(
        name = name,
        target = name + "_cslB",
        impl = _cslB_static_sharing_test_impl,
    )

def _cslB_static_sharing_test_impl(env, target):
    env.expect.that_target(target).has_provider(CcSharedLibraryInfo)
    csl_info = target[CcSharedLibraryInfo]

    # Derive labels
    test_name = target.label.name[:-5]  # remove "_cslB"
    libB_label = target.label.same_package_label(test_name + "_libB")
    libC_label = target.label.same_package_label(test_name + "_libC")

    env.expect.that_collection([str(e) for e in csl_info.exports]).contains_exactly([str(libB_label), str(libC_label)])
    if hasattr(csl_info, "link_once_static_libs"):
        static_libs = [str(l) for l in csl_info.link_once_static_libs]
        env.expect.that_collection(static_libs).contains_exactly([str(libB_label), str(libC_label)])

def _pyext_static_sharing_test_impl(env, target):
    env.expect.that_target(target).has_provider(CcSharedLibraryInfo)
    csl_info = target[CcSharedLibraryInfo]

    # Derive labels
    test_name = target.label.name[:-7]  # remove "_pyextA"
    libA_label = target.label.same_package_label(test_name + "_libA")
    libB_label = target.label.same_package_label(test_name + "_libB")
    libC_label = target.label.same_package_label(test_name + "_libC")

    env.expect.that_collection([str(e) for e in csl_info.exports]).contains_exactly([str(libA_label)])
    if hasattr(csl_info, "link_once_static_libs"):
        static_libs = [str(l) for l in csl_info.link_once_static_libs]
        env.expect.that_collection(static_libs).contains(str(libA_label))
        env.expect.that_collection(static_libs).contains_none_of([str(libB_label), str(libC_label)])

def dependency_graph_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_csl_dynamic_deps_top,
            _test_pyext_dynamic_deps_top,
            _test_pyext_dynamic_deps_cslB,
            _test_pyext_dynamic_deps_cslC,
            _test_csl_static_sharing_top,
            _test_pyext_static_sharing_top,
            _test_pyext_static_sharing_cslB,
        ],
    )

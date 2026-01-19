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
"""PYTHON RULE IMPLEMENTATION ONLY: Do not use outside of the rule implementations and their tests.

Re-exports the restricted-use py_internal helper under its original name.

These may change at any time and are closely coupled to the rule implementation.
"""

# The py_internal object needs to be accessed only from "tools/build_defs/python", so
# we need to first put it there with a different name.
load("//tools/build_defs/python/private:py_internal_renamed.bzl", "py_internal_renamed")  # buildifier: disable=bzl-visibility

py_internal = py_internal_renamed

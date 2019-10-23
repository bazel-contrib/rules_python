# Copyright 2017 The Bazel Authors. All rights reserved.
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

"""Re-exports for some of the core Bazel Python rules.

This file is deprecated; please use the exports in defs.bzl instead. This is to
follow the new naming convention of putting core rules for a language
underneath @rules_<LANG>//<LANG>:defs.bzl. The exports in this file will be
disallowed in a future Bazel release by
`--incompatible_load_python_rules_from_bzl`.
"""

def py_library(*args, **kwargs):
    """See the Bazel core [py_library](
    https://docs.bazel.build/versions/master/be/python.html#py_library)
    documentation.

    Deprecated: This symbol will become unusuable when
    `--incompatible_load_python_rules_from_bzl` is enabled. Please use the
    symbols in `@rules_python//python:defs.bzl` instead.
    """

    # buildifier: disable=native-python
    native.py_library(*args, **kwargs)

def py_binary(*args, **kwargs):
    """See the Bazel core [py_binary](
    https://docs.bazel.build/versions/master/be/python.html#py_binary)
    documentation.

    Deprecated: This symbol will become unusuable when
    `--incompatible_load_python_rules_from_bzl` is enabled. Please use the
    symbols in `@rules_python//python:defs.bzl` instead.
    """

    # buildifier: disable=native-python
    native.py_binary(*args, **kwargs)

def py_test(*args, **kwargs):
    """See the Bazel core [py_test](
    https://docs.bazel.build/versions/master/be/python.html#py_test)
    documentation.

    Deprecated: This symbol will become unusuable when
    `--incompatible_load_python_rules_from_bzl` is enabled. Please use the
    symbols in `@rules_python//python:defs.bzl` instead.
    """

    # buildifier: disable=native-python
    native.py_test(*args, **kwargs)

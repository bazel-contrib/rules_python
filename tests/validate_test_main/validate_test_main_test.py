#!/usr/bin/env python3
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

import ast
import textwrap
import unittest

from python.private.py_test_main_validator import module_runs_something


def _runs_something(source: str) -> bool:
    tree = ast.parse(textwrap.dedent(source))
    return module_runs_something(tree)


class ModuleRunsSomethingTest(unittest.TestCase):
    def test_only_definitions_is_inert(self):
        self.assertFalse(
            _runs_something(
                """
                import unittest

                class MyTest(unittest.TestCase):
                    def test_foo(self):
                        self.assertTrue(True)
                """
            )
        )

    def test_definitions_with_assignments_is_inert(self):
        self.assertFalse(
            _runs_something(
                """
                import unittest

                CONSTANT = 5

                class MyTest(unittest.TestCase):
                    def test_foo(self):
                        pass

                def helper(): pass
                """
            )
        )

    def test_empty_module_is_inert(self):
        self.assertFalse(_runs_something(""))

    def test_docstring_only_is_inert(self):
        self.assertFalse(_runs_something('"""A module docstring."""'))

    def test_global_statement_is_inert(self):
        self.assertFalse(
            _runs_something(
                """
                global x

                class MyTest:
                    def test_foo(self):
                        pass
                """
            )
        )

    @unittest.skipUnless(
        hasattr(ast, "TypeAlias"), "PEP 695 type aliases require Python 3.12+"
    )
    def test_type_alias_is_inert(self):
        self.assertFalse(
            _runs_something(
                """
                type Alias = int

                class MyTest:
                    def test_foo(self):
                        pass
                """
            )
        )

    def test_if_name_main_guard_runs_something(self):
        self.assertTrue(
            _runs_something(
                """
                import unittest

                class MyTest(unittest.TestCase):
                    def test_foo(self):
                        pass

                if __name__ == "__main__":
                    unittest.main()
                """
            )
        )

    def test_bare_call_runs_something(self):
        self.assertTrue(
            _runs_something(
                """
                import pytest
                pytest.main()
                """
            )
        )

    def test_top_level_loop_runs_something(self):
        self.assertTrue(
            _runs_something(
                """
                def f(): pass

                for _ in range(1):
                    f()
                """
            )
        )


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
import ast
import textwrap
import unittest

from python.private.py_test_main_validator import module_runs_tests


def _runs_tests(source: str) -> bool:
    tree = ast.parse(textwrap.dedent(source))
    return module_runs_tests(tree)


class ModuleRunsTestsTest(unittest.TestCase):
    def test_only_definitions_is_rejected(self):
        self.assertFalse(
            _runs_tests(
                """
                import unittest

                class MyTest(unittest.TestCase):
                    def test_foo(self):
                        self.assertTrue(True)
                """
            )
        )

    def test_definitions_with_assignments_is_rejected(self):
        self.assertFalse(
            _runs_tests(
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

    def test_global_statement_with_definition_is_rejected(self):
        self.assertFalse(
            _runs_tests(
                """
                global x

                class MyTest:
                    def test_foo(self):
                        pass
                """
            )
        )

    def test_assert_statement_with_definition_is_rejected(self):
        # A bare `assert` with an inert condition runs no tests.
        self.assertFalse(
            _runs_tests(
                """
                assert True

                class MyTest:
                    def test_foo(self):
                        pass
                """
            )
        )

    def test_assert_statement_with_active_expression_runs_tests(self):
        # An assert whose condition runs a call actually runs the tests.
        self.assertTrue(
            _runs_tests(
                """
                import unittest

                class MyTest(unittest.TestCase):
                    def test_foo(self):
                        pass

                assert unittest.main()
                """
            )
        )

    @unittest.skipUnless(
        hasattr(ast, "TypeAlias"), "PEP 695 type aliases require Python 3.12+"
    )
    def test_type_alias_with_definition_is_rejected(self):
        self.assertFalse(
            _runs_tests(
                """
                type Alias = int

                class MyTest:
                    def test_foo(self):
                        pass
                """
            )
        )

    def test_type_checking_block_with_definition_is_rejected(self):
        # `if TYPE_CHECKING:` guarding typing-only imports is inert; with a test
        # definition and no runner, the module is still rejected.
        self.assertFalse(
            _runs_tests(
                """
                from typing import TYPE_CHECKING
                import unittest

                if TYPE_CHECKING:
                    from typing import Any

                class MyTest(unittest.TestCase):
                    def test_foo(self):
                        pass
                """
            )
        )

    def test_try_except_import_error_with_definition_is_rejected(self):
        # `try: import foo except ImportError:` optional imports are inert.
        self.assertFalse(
            _runs_tests(
                """
                try:
                    import foo
                except ImportError:
                    foo = None

                import unittest

                class MyTest(unittest.TestCase):
                    def test_foo(self):
                        pass
                """
            )
        )

    def test_definitions_with_active_assignment_runs_tests(self):
        # An assignment whose value runs a call actually runs the tests.
        self.assertTrue(
            _runs_tests(
                """
                import unittest

                class MyTest(unittest.TestCase):
                    def test_foo(self):
                        pass

                exit_code = unittest.main()
                """
            )
        )

    def test_definitions_with_active_expression_runs_tests(self):
        self.assertTrue(
            _runs_tests(
                """
                import sys
                import unittest

                class MyTest(unittest.TestCase):
                    def test_foo(self):
                        pass

                sys.exit(unittest.main())
                """
            )
        )

    def test_if_block_invoking_runner_runs_tests(self):
        # A runner call inside an `if` body must still count as active.
        self.assertTrue(
            _runs_tests(
                """
                import sys
                import unittest

                class MyTest(unittest.TestCase):
                    def test_foo(self):
                        pass

                if "--run" in sys.argv:
                    unittest.main()
                """
            )
        )

    def test_import_only_module_is_allowed(self):
        # A module that defines nothing and only imports other modules is not
        # the "defined but never run" case, so it is allowed.
        self.assertTrue(
            _runs_tests(
                """
                import my_tests
                from my_pkg.tests import suite
                """
            )
        )

    def test_imports_and_assignments_without_definitions_is_allowed(self):
        self.assertTrue(
            _runs_tests(
                """
                import my_tests

                CONSTANT = 5
                """
            )
        )

    def test_empty_module_is_allowed(self):
        self.assertTrue(_runs_tests(""))

    def test_docstring_only_is_allowed(self):
        self.assertTrue(_runs_tests('"""A module docstring."""'))

    def test_if_name_main_guard_runs_tests(self):
        self.assertTrue(
            _runs_tests(
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

    def test_bare_call_runs_tests(self):
        self.assertTrue(
            _runs_tests(
                """
                import pytest
                pytest.main()
                """
            )
        )

    def test_top_level_loop_runs_tests(self):
        self.assertTrue(
            _runs_tests(
                """
                def f(): pass

                for _ in range(1):
                    f()
                """
            )
        )


if __name__ == "__main__":
    unittest.main()

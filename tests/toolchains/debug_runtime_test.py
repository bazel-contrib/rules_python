import sys
import sysconfig
import unittest

from tests.toolchains import (
    debug_ext,  # pyrefly: ignore[missing-module-attribute]
)


class DebugRuntimeTest(unittest.TestCase):
    def test_interpreter_is_a_debug_build(self):
        self.assertEqual("d", sys.abiflags)

    def test_extension_uses_the_debug_abi(self):
        self.assertEqual(42, debug_ext.answer())
        self.assertTrue(
            debug_ext.__file__.endswith(sysconfig.get_config_var("EXT_SUFFIX")),
            debug_ext.__file__,
        )


if __name__ == "__main__":
    unittest.main()


import echo_ext

import unittest



class ExtensionTest(unittest.TestCase):

    def test_echo_extension(self):
        self.assertEqual(echo.echo(42, "str"), tuple(42, "str"))
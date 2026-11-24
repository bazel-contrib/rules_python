import unittest

import contourpy
import markupsafe
import tabulate
import tiny_meson


class NativeSdistTest(unittest.TestCase):
    def test_markupsafe_c_extension(self):
        # Verify the compiled C speedup extension was built and loaded.
        self.assertTrue(hasattr(markupsafe, "_speedups"))
        self.assertEqual(str(markupsafe.escape("<b>hi</b>")), "&lt;b&gt;hi&lt;/b&gt;")

    def test_tabulate(self):
        table = tabulate.tabulate([["a", 1], ["b", 2]], headers=["k", "v"])
        self.assertIn("a", table)
        self.assertIn("2", table)

    def test_tiny_meson_c_and_cpp_extensions(self):
        self.assertEqual(tiny_meson.add_ints(2, 3), 5)
        self.assertEqual(tiny_meson.mul_ints(4, 5), 20)

    def test_contourpy_meson_cpp_extension(self):
        # Exercises pip.parse + pip.whl_mods with a PyPI meson-python C++ sdist.
        cg = contourpy.contour_generator(z=[[0.0, 1.0], [1.0, 0.0]])
        lines = cg.lines(0.5)
        self.assertTrue(lines)


if __name__ == "__main__":
    unittest.main()

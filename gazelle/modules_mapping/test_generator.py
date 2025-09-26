import pathlib
import unittest

from generator import Generator


class GeneratorTest(unittest.TestCase):
    def test_generator(self):
        whl = pathlib.Path(__file__).parent / "pytest-8.3.3-py3-none-any.whl"
        gen = Generator(None, None, {}, False, False)
        gen.dig_wheel(whl)
        self.assertLessEqual(
            {
                "_pytest": "pytest",
                "_pytest.__init__": "pytest",
                "_pytest._argcomplete": "pytest",
                "_pytest.config.argparsing": "pytest",
            }.items(),
            gen.mapping.items(),
        )

    def test_stub_generator(self):
        whl = pathlib.Path(__file__).parent / "django_types-0.19.1-py3-none-any.whl"
        gen = Generator(None, None, {}, True, False)
        gen.dig_wheel(whl)
        self.assertLessEqual(
            {
                "django_types": "django_types",
            }.items(),
            gen.mapping.items(),
        )

    def test_stub_excluded(self):
        whl = pathlib.Path(__file__).parent / "django_types-0.19.1-py3-none-any.whl"
        gen = Generator(None, None, {}, False, False)
        gen.dig_wheel(whl)
        self.assertEqual(
            {}.items(),
            gen.mapping.items(),
        )

    def test_ignore_native_libs(self):
        # Test the ignore_native_libs functionality with the module_for_path method
        gen_with_native_libs = Generator(None, None, {}, False, False)
        gen_without_native_libs = Generator(None, None, {}, False, True)

        # Simulate a Python file - should be included in both cases
        gen_with_native_libs.module_for_path("cv2/__init__.py", "opencv_python_headless-4.8.1-cp310-cp310-linux_x86_64.whl")
        gen_without_native_libs.module_for_path("cv2/__init__.py", "opencv_python_headless-4.8.1-cp310-cp310-linux_x86_64.whl")

        # Simulate a native library - should be included only when ignore_native_libs=False
        gen_with_native_libs.module_for_path("opencv_python_headless.libs/libopenblas-r0-f650aae0.so", "opencv_python_headless-4.8.1-cp310-cp310-linux_x86_64.whl")
        gen_without_native_libs.module_for_path("opencv_python_headless.libs/libopenblas-r0-f650aae0.so", "opencv_python_headless-4.8.1-cp310-cp310-linux_x86_64.whl")

        # Both should have the Python module mapping
        self.assertIn("cv2", gen_with_native_libs.mapping)
        self.assertIn("cv2", gen_without_native_libs.mapping)

        # Only gen_with_native_libs should have the native library mapping
        self.assertIn("opencv_python_headless.libs.libopenblas-r0-f650aae0", gen_with_native_libs.mapping)
        self.assertNotIn("opencv_python_headless.libs.libopenblas-r0-f650aae0", gen_without_native_libs.mapping)


if __name__ == "__main__":
    unittest.main()

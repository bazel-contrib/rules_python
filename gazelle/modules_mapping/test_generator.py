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

    def test_skip_private_shared_objects(self):
        # Test the skip_private_shared_objects functionality with the module_for_path method
        gen_with_private_libs = Generator(None, None, {}, False, False)
        gen_without_private_libs = Generator(None, None, {}, False, True)

        # Simulate Python files - should be included in both cases
        gen_with_private_libs.module_for_path(
            "cv2/__init__.py",
            "opencv_python_headless-4.12.0.88-cp37-abi3-manylinux2014_x86_64.whl",
        )
        gen_without_private_libs.module_for_path(
            "cv2/__init__.py",
            "opencv_python_headless-4.12.0.88-cp37-abi3-manylinux2014_x86_64.whl",
        )
        gen_with_private_libs.module_for_path(
            "numpy/__init__.py", "numpy-2.2.6-cp310-cp310-manylinux_2_17_x86_64.whl"
        )
        gen_without_private_libs.module_for_path(
            "numpy/__init__.py", "numpy-2.2.6-cp310-cp310-manylinux_2_17_x86_64.whl"
        )

        # Real-world examples from wheels
        private_shared_objects = [
            "opencv_python_headless.libs/libopenblas-r0-f650aae0.so",
            "numpy.libs/libscipy_openblas64_-56d6093b.so",
        ]

        # Add all private shared objects to both generators
        for lib_path in private_shared_objects:
            wheel_name = (
                "opencv_python_headless-4.12.0.88"
                if "opencv" in lib_path
                else "numpy-2.2.6"
            )
            gen_with_private_libs.module_for_path(lib_path, f"{wheel_name}.whl")
            gen_without_private_libs.module_for_path(lib_path, f"{wheel_name}.whl")

        # Both should have the Python module mappings
        self.assertIn("cv2", gen_with_private_libs.mapping)
        self.assertIn("cv2", gen_without_private_libs.mapping)
        self.assertIn("numpy", gen_with_private_libs.mapping)
        self.assertIn("numpy", gen_without_private_libs.mapping)

        # Only gen_with_private_libs should have the private shared object mappings
        expected_private_mappings = [
            "opencv_python_headless.libs.libopenblas-r0-f650aae0",
            "numpy.libs.libscipy_openblas64_-56d6093b",
        ]

        for mapping in expected_private_mappings:
            self.assertIn(mapping, gen_with_private_libs.mapping)
            self.assertNotIn(mapping, gen_without_private_libs.mapping)


if __name__ == "__main__":
    unittest.main()

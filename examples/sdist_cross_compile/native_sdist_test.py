import importlib
import os
import pathlib
import sys
import tempfile
import unittest
import zipfile


def _find_runfiles_root() -> pathlib.Path:
    runfiles_dir = os.environ.get("TEST_SRCDIR") or os.environ.get("RUNFILES_DIR")
    if not runfiles_dir:
        raise AssertionError("Neither TEST_SRCDIR nor RUNFILES_DIR is set")
    return pathlib.Path(runfiles_dir)


class NativeSdistTest(unittest.TestCase):
    def _extract_wheels(self, dest: pathlib.Path, filenames: list[str]) -> None:
        root = _find_runfiles_root()
        for name in filenames:
            matches = list(root.rglob(name))
            self.assertTrue(matches, f"Expected wheel {name!r} under {root}")
            with zipfile.ZipFile(matches[0]) as zf:
                zf.extractall(dest)

    def test_setuptools_and_meson_c_cpp_extensions(self):
        with tempfile.TemporaryDirectory() as tmp:
            self._extract_wheels(
                pathlib.Path(tmp),
                ["tiny_setuptools.sdist_build.whl", "tiny_meson.sdist_build.whl"],
            )
            sys.path.insert(0, tmp)
            try:
                tiny_setuptools = importlib.import_module("tiny_setuptools")
                tiny_meson = importlib.import_module("tiny_meson")
                self.assertEqual(tiny_setuptools.sub_ints(10, 3), 7)
                self.assertEqual(tiny_meson.add_ints(2, 3), 5)
                self.assertEqual(tiny_meson.mul_ints(4, 5), 20)
            finally:
                sys.path.remove(tmp)


if __name__ == "__main__":
    unittest.main()

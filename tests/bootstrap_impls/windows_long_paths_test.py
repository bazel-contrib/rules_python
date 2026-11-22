"""Tests the bootstrap with Windows paths that need the \\?\\ prefix."""

from __future__ import annotations

import os
import shutil
import tempfile
import unittest

from tests.bootstrap_impls.bootstrap_template_loader import load_bootstrap

_PREFIX = "\\\\?\\"
# Over 260 characters, the limit without the prefix or LongPathsEnabled.
_LONG_REL_PATH = os.path.join(*["d" * 50] * 6)


@unittest.skipUnless(os.name == "nt", "Windows only")
class WindowsLongPathsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.bootstrap = load_bootstrap()
        # Use the fallback for when symlinks can't be created.
        self.bootstrap["_symlinks_supported"] = False
        self.temp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, _PREFIX + self.temp)

    def _write_long_file(self, root: str) -> str:
        path = os.path.join(root, _LONG_REL_PATH, "file.txt")
        os.makedirs(_PREFIX + os.path.dirname(path))
        with open(_PREFIX + path, "w") as f:
            f.write("hello")
        return path

    def test_prefix_is_only_added_to_long_paths(self) -> None:
        add_prefix = self.bootstrap["get_windows_path_with_unc_prefix"]
        self.assertEqual(add_prefix("C:\\short"), "C:\\short")
        long_path = "C:\\" + "a" * 300
        self.assertEqual(add_prefix(long_path), _PREFIX + long_path)
        self.assertEqual(
            add_prefix("\\\\server\\share\\" + "a" * 300),
            _PREFIX + "UNC\\server\\share\\" + "a" * 300,
        )

    def test_fallback_links_a_long_path(self) -> None:
        target = self._write_long_file(self.temp)
        link = os.path.join(self.temp, "link.txt")

        self.bootstrap["_symlink_exist_ok"](from_=link, to=target)

        with open(link) as f:
            self.assertEqual(f.read(), "hello")

    def test_symlink_tree_includes_long_paths(self) -> None:
        src = os.path.join(self.temp, "src")
        self._write_long_file(src)
        dest = os.path.join(self.temp, "dest")

        self.bootstrap["_symlink_tree"](link_from=dest, link_to=src)

        with open(_PREFIX + os.path.join(dest, _LONG_REL_PATH, "file.txt")) as f:
            self.assertEqual(f.read(), "hello")


if __name__ == "__main__":
    unittest.main()

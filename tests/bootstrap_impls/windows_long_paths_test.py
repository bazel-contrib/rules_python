"""Tests the bootstrap with Windows paths that need the \\?\\ prefix."""

from __future__ import annotations

import os
import shutil
import tempfile
import unittest
from unittest import mock

from tests.bootstrap_impls.bootstrap_template_loader import (
    load_bootstrap,
    load_functions,
)

_PREFIX = "\\\\?\\"
# Over 260 characters, the limit without the prefix or LongPathsEnabled.
_LONG_REL_PATH = os.path.join(*["d" * 50] * 6)
_HELPER = "get_windows_path_with_unc_prefix"


@unittest.skipUnless(os.name == "nt", "Windows only")
class PrefixHelperTest(unittest.TestCase):
    def _copies(self) -> dict:
        """Returns the globals of each copy of the helper."""
        names = [_HELPER, "_long_paths_enabled"]
        return {
            "stage 1": load_bootstrap(),
            "stage 2": load_functions(
                "python/private/stage2_bootstrap_template.py", names
            ),
            "zipapp": load_functions(
                "python/private/zipapp/zip_main_template.py", names
            ),
        }

    def test_prefix_is_only_added_when_needed(self) -> None:
        long_path = "C:\\" + "a" * 300
        unc_path = "\\\\server\\share\\" + "a" * 300
        for name, module in self._copies().items():
            add_prefix = module[_HELPER]
            with self.subTest(name, long_paths_enabled=False):
                module["_long_paths_enabled"] = lambda: False
                self.assertEqual(add_prefix("C:\\short"), "C:\\short")
                self.assertEqual(add_prefix(long_path), _PREFIX + long_path)
                self.assertEqual(
                    add_prefix(unc_path), _PREFIX + "UNC\\" + unc_path[2:]
                )
                self.assertEqual(add_prefix(_PREFIX + "C:\\x"), _PREFIX + "C:\\x")
            with self.subTest(name, long_paths_enabled=True):
                module["_long_paths_enabled"] = lambda: True
                self.assertEqual(add_prefix(long_path), long_path)

    def test_site_init_converts_unc_paths(self) -> None:
        module = load_functions(
            "python/private/site_init_template.py",
            ["_is_windows", "_get_windows_path_with_unc_prefix"],
        )
        add_prefix = module["_get_windows_path_with_unc_prefix"]
        self.assertEqual(add_prefix("C:\\x"), _PREFIX + "C:\\x")
        self.assertEqual(
            add_prefix("\\\\server\\share\\x"), _PREFIX + "UNC\\server\\share\\x"
        )


@unittest.skipUnless(os.name == "nt", "Windows only")
class LinkFallbackTest(unittest.TestCase):
    """Uses the real LongPathsEnabled setting, so it passes either way."""

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

    def test_links_a_long_file(self) -> None:
        target = self._write_long_file(self.temp)
        link = os.path.join(self.temp, "link.txt")

        self.bootstrap["_symlink_exist_ok"](from_=link, to=target)

        with open(link) as f:
            self.assertEqual(f.read(), "hello")

    def test_links_a_long_directory(self) -> None:
        target = os.path.dirname(self._write_long_file(self.temp))
        link = os.path.join(self.temp, "link")

        self.bootstrap["_symlink_exist_ok"](from_=link, to=target)

        self.assertEqual(os.listdir(link), ["file.txt"])

    def test_symlink_tree_includes_long_paths(self) -> None:
        src = os.path.join(self.temp, "src")
        self._write_long_file(src)
        dest = os.path.join(self.temp, "dest")

        self.bootstrap["_symlink_tree"](link_from=dest, link_to=src)

        with open(_PREFIX + os.path.join(dest, _LONG_REL_PATH, "file.txt")) as f:
            self.assertEqual(f.read(), "hello")

    def test_symlink_tree_keeps_short_targets_unprefixed(self) -> None:
        self.bootstrap["_symlinks_supported"] = True
        src = os.path.join(self.temp, "src")
        os.makedirs(os.path.join(src, "pkg"))
        target = os.path.join(src, "pkg", "mod.py")
        open(target, "w").close()

        with mock.patch("os.symlink") as symlink:
            self.bootstrap["_symlink_tree"](
                link_from=os.path.join(self.temp, "dest"), link_to=src
            )

        self.assertEqual(symlink.call_args.args[0], target)


if __name__ == "__main__":
    unittest.main()

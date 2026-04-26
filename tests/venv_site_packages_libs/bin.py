import importlib
import os
import sys
import sysconfig
import unittest
from pathlib import Path


class VenvSitePackagesLibraryTest(unittest.TestCase):
    def setUp(self):
        super().setUp()
        if sys.prefix == sys.base_prefix:
            raise AssertionError("Not running under a venv")
        self.venv = Path(sys.prefix)
        self.site_packages = Path(sysconfig.get_paths()["purelib"])

        is_windows = sys.platform == "win32"
        if is_windows:
            self.bin_dir_name = Path("Scripts")
            self.include_dir_name = Path("Include")
        else:
            self.bin_dir_name = Path("bin")
            self.include_dir_name = Path("include")

    def assert_venv_path_exists(self, rel_path):
        path = self.venv / rel_path
        self.assertTrue(
            path.exists(),
            f"Expected {path} to exist. {path.parent.name} contents: {list(path.parent.iterdir()) if path.parent.exists() else 'N/A'}",
        )

    def assert_imported_from_venv(self, module_name):
        module = importlib.import_module(module_name)
        self.assertEqual(module.__name__, module_name)
        self.assertIsNotNone(
            module.__file__,
            f"Expected module {module_name!r} to have"
            + f"__file__ set, but got None. {module=}",
        )
        self.assertTrue(
            module.__file__.startswith(str(self.venv)),
            f"\n{module_name} was imported, but not from the venv.\n"
            + f"       venv: {self.venv}\n"
            + f"module file: {module.__file__}\n"
            + "sys.path:\n"
            + "\n".join(sys.path),
        )
        return module

    def test_imported_from_venv(self):
        m = self.assert_imported_from_venv("pkgutil_top")
        self.assertEqual(m.WHOAMI, "pkgutil_top")

        m = self.assert_imported_from_venv("pkgutil_top.sub")
        self.assertEqual(m.WHOAMI, "pkgutil_top.sub")

        self.assert_imported_from_venv("nspkg.subnspkg.alpha")
        self.assert_imported_from_venv("nspkg.subnspkg.beta")
        self.assert_imported_from_venv("nspkg.subnspkg.gamma")
        self.assert_imported_from_venv("nspkg.subnspkg.delta")
        self.assert_imported_from_venv("single_file")
        self.assert_imported_from_venv("simple")
        m = self.assert_imported_from_venv("nested_with_pth")
        self.assertEqual(m.WHOAMI, "nested_with_pth")

    def test_data_is_included(self):
        self.assert_imported_from_venv("simple")
        module = importlib.import_module("simple")
        # Ensure that packages from simple v1 are not present
        files = [p.name for p in self.site_packages.glob("*")]
        self.assertIn("simple_v1_extras", files)

    def test_override_pkg(self):
        self.assert_imported_from_venv("simple")
        module = importlib.import_module("simple")
        self.assertEqual(
            "1.0.0",
            module.__version__,
        )

    def test_dirs_from_replaced_package_are_not_present(self):
        self.assert_imported_from_venv("simple")
        module = importlib.import_module("simple")
        dist_info_dirs = [p.name for p in self.site_packages.glob("simple*.dist-info")]
        self.assertEqual(
            ["simple-1.0.0.dist-info"],
            dist_info_dirs,
        )

        # Ensure that packages from simple v1 are not present
        files = [p.name for p in self.site_packages.glob("*")]
        self.assertNotIn("simple.libs", files)

    def test_data_from_another_pkg_is_included_via_copy_file(self):
        self.assert_imported_from_venv("simple")
        module = importlib.import_module("simple")
        # Ensure that packages from simple v1 are not present
        d = self.site_packages / "external_data"
        files = [p.name for p in d.glob("*")]
        self.assertIn("another_module_data.txt", files)

    def test_whl_with_data1_included(self):
        module = self.assert_imported_from_venv("whl_with_data1")
        site_packages_rel = self.site_packages.relative_to(self.venv)
        # purelib
        self.assert_venv_path_exists(site_packages_rel / "whl_with_data1/data_file.txt")

        # platlib
        self.assert_venv_path_exists(
            site_packages_rel / "whl_with_data1/platlib_file.txt"
        )

        venv_root = self.venv

        # data
        self.assert_venv_path_exists("whl_with_data1/data_data_file.txt")

        # scripts
        self.assert_venv_path_exists(self.bin_dir_name / "whl_script.sh")

        # headers
        self.assert_venv_path_exists(
            self.include_dir_name / "whl_with_data1/header_file.h"
        )

    def test_whl_with_data2_included(self):
        module = self.assert_imported_from_venv("whl_with_data2")

        site_packages_rel = self.site_packages.relative_to(self.venv)
        self.assert_venv_path_exists(site_packages_rel / "whl_with_data2/data_file.txt")

        self.assert_venv_path_exists(self.bin_dir_name / "whl_script.sh")

        # Ensure that `data` files are unpacked in `venv/root/`
        # and then linked as `venv/whl_with_data1/data_data_file.txt`.
        self.assert_venv_path_exists("whl_with_data2/data_data_file.txt")

        self.assert_venv_path_exists(
            self.include_dir_name / "whl_with_data2/header_file.h"
        )

    def test_whl_with_data_overlap(self):
        self.assert_venv_path_exists("overlap/both.txt")
        self.assert_venv_path_exists("overlap/data1.txt")
        self.assert_venv_path_exists("overlap/data2.txt")

        self.assert_venv_path_exists(self.bin_dir_name / "overlap/both.sh")
        self.assert_venv_path_exists(self.bin_dir_name / "overlap/script1.sh")
        self.assert_venv_path_exists(self.bin_dir_name / "overlap/script2.sh")

        self.assert_venv_path_exists(self.include_dir_name / "overlap/both.h")
        self.assert_venv_path_exists(self.include_dir_name / "overlap/header1.h")
        self.assert_venv_path_exists(self.include_dir_name / "overlap/header2.h")


if __name__ == "__main__":
    unittest.main()

import importlib
import os
import sys
import unittest
from pathlib import Path


class VenvSitePackagesLibraryTest(unittest.TestCase):
    def setUp(self):
        super().setUp()
        if sys.prefix == sys.base_prefix:
            raise AssertionError("Not running under a venv")
        self.venv = sys.prefix

    def assert_imported_from_venv(self, module_name):
        module = importlib.import_module(module_name)
        self.assertEqual(module.__name__, module_name)
        self.assertIsNotNone(
            module.__file__,
            f"Expected module {module_name!r} to have"
            + f"__file__ set, but got None. {module=}",
        )
        self.assertTrue(
            module.__file__.startswith(self.venv),
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
        module_path = Path(module.__file__)

        site_packages = module_path.parent.parent

        # Ensure that packages from simple v1 are not present
        files = [p.name for p in site_packages.glob("*")]
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
        module_path = Path(module.__file__)

        site_packages = module_path.parent.parent
        dist_info_dirs = [p.name for p in site_packages.glob("simple*.dist-info")]
        self.assertEqual(
            ["simple-1.0.0.dist-info"],
            dist_info_dirs,
        )

        # Ensure that packages from simple v1 are not present
        files = [p.name for p in site_packages.glob("*")]
        self.assertNotIn("simple.libs", files)

    def test_data_from_another_pkg_is_included_via_copy_file(self):
        self.assert_imported_from_venv("simple")
        module = importlib.import_module("simple")
        module_path = Path(module.__file__)

        site_packages = module_path.parent.parent
        # Ensure that packages from simple v1 are not present
        d = site_packages / "external_data"
        files = [p.name for p in d.glob("*")]
        self.assertIn("another_module_data.txt", files)

    @unittest.skipIf(
        os.environ.get("BZLMOD_ENABLED") == "0",
        "whl_with_data1 is only available with bzlmod",
    )
    def test_whl_with_data1_included(self):
        module = self.assert_imported_from_venv("whl_with_data1")
        module_path = Path(module.__file__)
        site_packages = module_path.parent.parent

        # purelib
        data_file = site_packages / "whl_with_data1" / "data_file.txt"
        self.assertTrue(data_file.exists(), f"Expected {data_file} to exist")

        # platlib
        platlib_file = site_packages / "whl_with_data1" / "platlib_file.txt"
        self.assertTrue(platlib_file.exists(), f"Expected {platlib_file} to exist")

        venv_root = Path(self.venv)

        is_windows = sys.platform == "win32"
        if is_windows:
            bin_dir_name = "Scripts"
            include_dir_name = "Include"
        else:
            bin_dir_name = "bin"
            include_dir_name = "include"

        # data
        data_data_file = venv_root / "data" / "whl_with_data1" / "data_data_file.txt"
        self.assertTrue(
            data_data_file.exists(),
            f"Expected {data_data_file} to exist. venv_root contents: {list(venv_root.iterdir()) if venv_root.exists() else 'N/A'}. os.name={os.name}, sys.platform={sys.platform}",
        )

        # scripts
        script_file = venv_root / bin_dir_name / "whl_script.sh"
        self.assertTrue(
            script_file.exists(),
            f"Expected {script_file} to exist. {bin_dir_name} contents: {list((venv_root / bin_dir_name).iterdir()) if (venv_root / bin_dir_name).exists() else 'N/A'}",
        )

        # headers
        header_file = venv_root / include_dir_name / "whl_with_data1" / "header_file.h"
        self.assertTrue(
            header_file.exists(),
            f"Expected {header_file} to exist. {include_dir_name} contents: {list((venv_root / include_dir_name).iterdir()) if (venv_root / include_dir_name).exists() else 'N/A'}",
        )




    @unittest.skipIf(
        os.environ.get("BZLMOD_ENABLED") == "0",
        "whl_with_data1 is only available with bzlmod",
    )
    def test_whl_with_data2_included(self):
        module = self.assert_imported_from_venv("whl_with_data2")

        module_path = Path(module.__file__)
        site_packages = module_path.parent.parent
        venv_root = Path(self.venv)

        data_file = site_packages / "whl_with_data2" / "data_file.txt"
        self.assertTrue(data_file.exists(), data_file)
        self.assertTrue(data_file.is_file(), data_file)

        platlib_file = site_packages / "whl_with_data2" / "platlib_file.txt"
        self.assertTrue(platlib_file.exists(), platlib_file)
        self.assertTrue(platlib_file.is_file(), platlib_file)

        script_file = venv_root / "bin" / "whl_script.sh"
        self.assertTrue(script_file.exists(), script_file)
        self.assertTrue(script_file.is_file(), script_file)

        # Ensure that `data` files are unpacked in `venv/data/`
        # and then linked as `venv/data/whl_with_data1/data_data_file.txt`.
        data_data_file = venv_root / "data" / "whl_with_data2" / "data_data_file.txt"
        self.assertTrue(data_data_file.exists(), data_data_file)
        self.assertTrue(data_data_file.is_file(), data_data_file)


        is_windows = sys.platform == "win32"
        if is_windows:
            include_dir_name = "Include"
        else:
            include_dir_name = "include"

        header_file = (
            venv_root / include_dir_name / "whl_with_data2" / "header_file.h"
        )
        self.assertTrue(header_file.exists(), header_file)
        self.assertTrue(header_file.is_file(), header_file)


    @unittest.skipIf(
        os.environ.get("BZLMOD_ENABLED") == "0",
        "whl_with_data is only available with bzlmod",
    )
    def test_whl_with_data_overlap(self):
        venv_root = Path(self.venv)

        overlap_both = venv_root / "data" / "overlap" / "both.txt"
        self.assertTrue(overlap_both.exists(), f"Expected {overlap_both} to exist")

        overlap_data1 = venv_root / "data" / "overlap" / "data1.txt"
        self.assertTrue(overlap_data1.exists(), f"Expected {overlap_data1} to exist")

        overlap_data2 = venv_root / "data" / "overlap" / "data2.txt"
        self.assertTrue(overlap_data2.exists(), f"Expected {overlap_data2} to exist")

if __name__ == "__main__":
    unittest.main()

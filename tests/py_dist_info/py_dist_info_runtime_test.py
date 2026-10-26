import importlib.metadata
import unittest
import zipfile

from python.runfiles import runfiles


class PyDistInfoRuntimeTest(unittest.TestCase):
    def test_version_and_metadata(self):
        self.assertEqual(importlib.metadata.version("sample_pkg"), "3.4.5")
        meta = importlib.metadata.metadata("sample_pkg")
        self.assertEqual(meta["Name"], "sample_pkg")
        self.assertEqual(meta["Version"], "3.4.5")
        self.assertEqual(
            meta["Summary"], "Sample package for testing py_dist_info"
        )

    def test_entry_points(self):
        eps = importlib.metadata.entry_points(
            group="sample_pkg.plugins",
            name="default_plugin",
        )
        ep_list = list(eps)
        self.assertEqual(len(ep_list), 1)
        fn = ep_list[0].load()
        self.assertEqual(fn(), "plugin_ok")

    def test_wheel_reuses_dist_info(self):
        whl_path = (
            runfiles.CreateOrRaise().root()
            / "rules_python/tests/py_dist_info/sample_pkg-3.4.5-py3-none-any.whl"
        )
        with zipfile.ZipFile(whl_path) as zf:
            metadata = zf.read("sample_pkg-3.4.5.dist-info/METADATA").decode(
                "utf-8"
            )
            entry_points = zf.read(
                "sample_pkg-3.4.5.dist-info/entry_points.txt"
            ).decode("utf-8")

        self.assertIn("Name: sample_pkg\n", metadata)
        self.assertIn("Version: 3.4.5\n", metadata)
        self.assertIn(
            "Summary: Sample package for testing py_dist_info\n", metadata
        )
        self.assertEqual(
            entry_points,
            "[sample_pkg.plugins]\n"
            "default_plugin = tests.py_dist_info.sample_pkg:run_plugin",
        )


if __name__ == "__main__":
    unittest.main()

import importlib.metadata
import unittest


class PyDistInfoRuntimeTest(unittest.TestCase):
    def test_version_and_metadata(self):
        self.assertEqual(importlib.metadata.version("sample_pkg"), "3.4.5")
        meta = importlib.metadata.metadata("sample_pkg")
        self.assertEqual(meta["Name"], "sample_pkg")
        self.assertEqual(meta["Version"], "3.4.5")

    def test_entry_points(self):
        eps = importlib.metadata.entry_points(
            group="sample_pkg.plugins",
            name="default_plugin",
        )
        ep_list = list(eps)
        self.assertEqual(len(ep_list), 1)
        fn = ep_list[0].load()
        self.assertEqual(fn(), "plugin_ok")


if __name__ == "__main__":
    unittest.main()

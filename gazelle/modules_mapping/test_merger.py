import json
import pathlib
import tempfile
import unittest

from merger import merge_modules_mappings


class MergerTest(unittest.TestCase):
    _tmpdir: tempfile.TemporaryDirectory

    def setUp(self) -> None:
        super().setUp()
        self._tmpdir = tempfile.TemporaryDirectory()

    def tearDown(self) -> None:
        super().tearDown()
        self._tmpdir.cleanup()
        del self._tmpdir

    @property
    def tmppath(self) -> pathlib.Path:
        return pathlib.Path(self._tmpdir.name)

    def make_input(self, mapping: dict[str, str]) -> pathlib.Path:
        _fd, file = tempfile.mkstemp(suffix=".json", dir=self._tmpdir.name)
        path = pathlib.Path(file)
        path.write_text(json.dumps(mapping))
        return path

    def test_merger(self):
        output_path = self.tmppath / "output.json"
        merge_modules_mappings(
            [
                self.make_input(
                    {
                        "_pytest": "pytest",
                        "_pytest.__init__": "pytest",
                        "_pytest._argcomplete": "pytest",
                        "_pytest.config.argparsing": "pytest",
                    }
                ),
                self.make_input({"django_types": "django_types"}),
            ],
            output_path,
        )

        self.assertEqual(
            {
                "_pytest": "pytest",
                "django_types": "django_types",
            },
            json.loads(output_path.read_text()),
        )

    def test_merger_keeps_distinct_namespace_package_submodules(self):
        # Regression test for https://github.com/bazel-contrib/rules_python/issues/3528.
        #
        # Two wheels ("bosdyn_client" and "bosdyn_orbit") both contribute to the
        # "bosdyn" namespace package, each shipping their own "bosdyn" entry
        # (from the namespace package's __init__.py) alongside their own
        # wheel-specific submodule. Since https://github.com/bazel-contrib/rules_python/pull/3415,
        # each wheel's mapping is generated (and, before this fix, simplified)
        # independently, so the merge must not let one wheel's "bosdyn" entry
        # clobber the other's more specific submodule entries.
        output_path = self.tmppath / "output.json"
        merge_modules_mappings(
            [
                self.make_input(
                    {
                        "bosdyn": "bosdyn_client",
                        "bosdyn.client": "bosdyn_client",
                        "bosdyn.client.control": "bosdyn_client",
                    }
                ),
                self.make_input(
                    {
                        "bosdyn": "bosdyn_orbit",
                        "bosdyn.orbit": "bosdyn_orbit",
                        "bosdyn.orbit.util": "bosdyn_orbit",
                    }
                ),
            ],
            output_path,
        )

        # "bosdyn.orbit"/"bosdyn.orbit.util" are redundant with the top-level
        # "bosdyn" -> "bosdyn_orbit" entry and get collapsed away, but
        # "bosdyn.client" must survive since it resolves to a different wheel
        # than the top-level "bosdyn" entry.
        self.assertEqual(
            {
                "bosdyn": "bosdyn_orbit",
                "bosdyn.client": "bosdyn_client",
            },
            json.loads(output_path.read_text()),
        )


if __name__ == "__main__":
    unittest.main()

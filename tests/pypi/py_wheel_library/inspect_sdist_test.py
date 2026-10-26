"""Unit tests for inspect_sdist."""

from __future__ import annotations

import io
import pathlib
import tarfile
import tempfile
import unittest

import inspect_sdist

from python.runfiles import runfiles


def _make_sdist_tar(path: pathlib.Path, files: dict[str, str]) -> pathlib.Path:
    with tarfile.open(path, "w:gz") as tf:
        for name, content in files.items():
            data = content.encode("utf-8")
            info = tarfile.TarInfo(name=name)
            info.size = len(data)
            info.mode = 0o644
            tf.addfile(info, io.BytesIO(data))
    return path


class InspectSdistTest(unittest.TestCase):
    def test_inspect_generated_sdist(self):
        rf = runfiles.Create()
        assert rf is not None
        sdist_rloc = rf.Rlocation(
            "rules_python/tests/pypi/py_wheel_library/sdist_demo-main.tar.gz"
        )
        assert sdist_rloc is not None
        info = inspect_sdist.inspect_sdist(pathlib.Path(sdist_rloc))
        self.assertEqual(info["site_paths"], ["sdist_demo"])

    def test_inspect_pep420_namespace_and_pyproject(self):
        with tempfile.TemporaryDirectory() as tmp:
            sdist = _make_sdist_tar(
                pathlib.Path(tmp) / "acme_sub-2.0.0.tar.gz",
                {
                    "acme_sub-2.0.0/pyproject.toml": (
                        "[build-system]\n"
                        'requires = ["setuptools>=61", "wheel"]\n'
                        'build-backend = "setuptools.build_meta"\n'
                        "[project]\n"
                        'name = "acme-sub"\n'
                        'version = "2.0.0"\n'
                        'dependencies = ["requests>=2.0"]\n'
                        "[project.optional-dependencies]\n"
                        'dev = ["pytest"]\n'
                        "[project.scripts]\n"
                        'acme-cli = "acme.sub.cli:main"\n'
                    ),
                    "acme_sub-2.0.0/src/acme/sub/__init__.py": "X = 1\n",
                    "acme_sub-2.0.0/src/acme/sub/cli.py": "def main(): pass\n",
                },
            )
            info = inspect_sdist.inspect_sdist(sdist)
            self.assertEqual(info["build_requires"], ["setuptools>=61", "wheel"])
            self.assertIn("requests>=2.0", info["requires_dist"])
            self.assertIn('pytest ; extra == "dev"', info["requires_dist"])
            self.assertEqual(info["provides_extra"], ["dev"])
            self.assertEqual(info["site_paths"], ["acme/sub"])
            self.assertEqual(info["namespace_package_files"], [])
            self.assertIn("acme-cli = acme.sub.cli:main", info["entry_points_content"])

    def test_inspect_pkgutil_namespace_and_egg_info(self):
        with tempfile.TemporaryDirectory() as tmp:
            sdist = _make_sdist_tar(
                pathlib.Path(tmp) / "ns_pkg-1.0.tar.gz",
                {
                    "ns_pkg-1.0/ns_pkg.egg-info/requires.txt": (
                        "six\n\n[test]\nmock\n"
                    ),
                    "ns_pkg-1.0/ns_pkg.egg-info/top_level.txt": "ns\nzope\ntools\nstale_ghost\n",
                    "ns_pkg-1.0/ns/__init__.py": (
                        "__path__ = __import__('pkgutil').extend_path(__path__, __name__)\n"
                    ),
                    "ns_pkg-1.0/ns/leaf/__init__.py": "VAL = 42\n",
                    "ns_pkg-1.0/zope/__init__.py": (
                        "__import__('pkg_resources').declare_namespace(__name__)\n"
                    ),
                    "ns_pkg-1.0/zope/interface/__init__.py": "IFACE = 1\n",
                    "ns_pkg-1.0/tools/__init__.py": "T = 1\n",
                },
            )
            info = inspect_sdist.inspect_sdist(sdist)
            self.assertIn("six", info["requires_dist"])
            self.assertIn('mock ; extra == "test"', info["requires_dist"])
            self.assertEqual(info["site_paths"], ["ns/leaf", "tools", "zope/interface"])
            self.assertEqual(
                info["namespace_package_files"], ["ns/__init__.py", "zope/__init__.py"]
            )

    def test_inspect_src_module_and_maturin_python_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            flit_sdist = _make_sdist_tar(
                pathlib.Path(tmp) / "typing_extensions-4.8.0.tar.gz",
                {
                    "typing_extensions-4.8.0/pyproject.toml": (
                        "[build-system]\n"
                        'requires = ["flit_core >=3.4,<4"]\n'
                        'build-backend = "flit_core.buildapi"\n'
                    ),
                    "typing_extensions-4.8.0/src/typing_extensions.py": "X = 1\n",
                },
            )
            self.assertEqual(
                inspect_sdist.inspect_sdist(flit_sdist)["site_paths"],
                ["typing_extensions.py"],
            )

            maturin_sdist = _make_sdist_tar(
                pathlib.Path(tmp) / "pydantic_core-2.10.0.tar.gz",
                {
                    "pydantic_core-2.10.0/pyproject.toml": (
                        "[build-system]\n"
                        'requires = ["maturin>=1.0,<2.0"]\n'
                        'build-backend = "maturin"\n'
                        "[tool.maturin]\n"
                        'python-source = "python"\n'
                    ),
                    "pydantic_core-2.10.0/src/lib.rs": "fn main() {}\n",
                    "pydantic_core-2.10.0/python/pydantic_core/__init__.py": "X = 1\n",
                },
            )
            self.assertEqual(
                inspect_sdist.inspect_sdist(maturin_sdist)["site_paths"],
                ["pydantic_core"],
            )

    def test_pkg_info_pep643_dynamic_and_invalid_toml(self):
        with tempfile.TemporaryDirectory() as tmp:
            dyn_sdist = _make_sdist_tar(
                pathlib.Path(tmp) / "dyn_pkg-1.0.tar.gz",
                {
                    "dyn_pkg-1.0/PKG-INFO": (
                        "Metadata-Version: 2.2\n"
                        "Name: dyn-pkg\n"
                        "Version: 1.0\n"
                        "Dynamic: Requires-Dist\n"
                    ),
                    "dyn_pkg-1.0/dyn_pkg.egg-info/requires.txt": "urllib3>=1.26\n",
                    "dyn_pkg-1.0/dyn_pkg/__init__.py": "X = 1\n",
                },
            )
            self.assertEqual(
                inspect_sdist.inspect_sdist(dyn_sdist)["requires_dist"],
                ["urllib3>=1.26"],
            )

            bad_toml_sdist = _make_sdist_tar(
                pathlib.Path(tmp) / "bad_toml-1.0.tar.gz",
                {
                    "bad_toml-1.0/pyproject.toml": "[project\nname = 'broken'\n",
                    "bad_toml-1.0/bad_toml/__init__.py": "X = 1\n",
                },
            )
            with self.assertRaisesRegex(ValueError, "Failed to parse pyproject.toml"):
                inspect_sdist.inspect_sdist(bad_toml_sdist)

            # Positive pkg_resources.declare_namespace(__name__) vs negative def declare_namespace
            # plus stale 'dist' in top_level.txt and package_dir remapping.
            ns_and_remapped = _make_sdist_tar(
                pathlib.Path(tmp) / "combo_sdist-1.0.tar.gz",
                {
                    "combo_sdist-1.0/combo.egg-info/top_level.txt": (
                        "dist\nfoo\nns_root\npkg_resources\nremapped_pkg\n"
                    ),
                    "combo_sdist-1.0/foo_impl/__init__.py": "from .foo import *\n",
                    "combo_sdist-1.0/foo_impl/foo.py": "F = 1\n",
                    "combo_sdist-1.0/ns_root/__init__.py": (
                        "__import__('pkg_resources').declare_namespace(__name__)\n"
                    ),
                    "combo_sdist-1.0/ns_root/child_a/__init__.py": "A = 1\n",
                    "combo_sdist-1.0/pkg_resources/__init__.py": (
                        "def declare_namespace(packageName):\n    pass\n"
                    ),
                    "combo_sdist-1.0/pkg_resources/_vendor/__init__.py": "V = 1\n",
                    "combo_sdist-1.0/lib/remapped_pkg/__init__.py": "R = 1\n",
                },
            )
            combo_res = inspect_sdist.inspect_sdist(ns_and_remapped)
            self.assertEqual(
                combo_res["site_paths"],
                ["foo", "ns_root/child_a", "pkg_resources", "remapped_pkg"],
            )
            self.assertEqual(
                combo_res["namespace_package_files"],
                ["ns_root/__init__.py"],
            )


if __name__ == "__main__":
    unittest.main()

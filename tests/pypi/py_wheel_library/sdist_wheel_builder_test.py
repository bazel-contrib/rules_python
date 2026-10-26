"""Unit tests for sdist_wheel_builder and py_sdist_wheel."""

from __future__ import annotations

import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
import zipfile

import sdist_wheel_builder

from python.runfiles import runfiles
from tests.pypi.py_wheel_library.make_test_sdist import write_sdist_tar


def _builder_env() -> dict[str, str]:
    builder_dir = str(pathlib.Path(sdist_wheel_builder.__file__ or "").resolve().parent)
    return {
        **os.environ,
        "PYTHONDONTWRITEBYTECODE": "1",
        "PYTHONPATH": builder_dir,
    }


class SdistWheelBuilderTest(unittest.TestCase):
    def test_built_sdist_demo_whldir_and_whl_file(self):
        rf = runfiles.Create()
        assert rf is not None
        whldir_rloc = rf.Rlocation(
            "rules_python/tests/pypi/py_wheel_library/sdist_demo-0.5.0.whldir"
        )
        assert whldir_rloc is not None
        whls = list(pathlib.Path(whldir_rloc).glob("*.whl"))
        self.assertEqual(len(whls), 1)
        with zipfile.ZipFile(whls[0]) as zf:
            init_text = zf.read("sdist_demo/__init__.py").decode("utf-8")
            self.assertIn('GREETING = "patched_before_build"', init_text)

        # Verify the regular .sdist_build.whl File output (:whl) has identical
        # bytes, satisfies Gazelle modules_mapping get_wheel_name, and works
        # with whl_filegroup.
        whl_file_rloc = rf.Rlocation(
            "rules_python/tests/pypi/py_wheel_library/sdist_demo-0.5.0.sdist_build.whl"
        )
        assert whl_file_rloc is not None
        whl_file_path = pathlib.Path(whl_file_rloc)
        self.assertTrue(whl_file_path.is_file())
        self.assertEqual(whl_file_path.read_bytes(), whls[0].read_bytes())
        # Gazelle modules_mapping get_wheel_name check: suffix == ".whl" and prefix before "-" is dist
        self.assertEqual(whl_file_path.suffix, ".whl")
        self.assertEqual(
            whl_file_path.name[: whl_file_path.name.find("-")], "sdist_demo"
        )
        # PEP 427 wheel filename check: only 1 '-' so pip/uv reject it as invalid wheel filename
        self.assertLess(whl_file_path.stem.count("-"), 4)

        whl_fg_rloc = rf.Rlocation(
            "rules_python/tests/pypi/py_wheel_library/sdist_demo_whl_fg/sdist_demo/__init__.py"
        )
        assert whl_fg_rloc is not None
        self.assertIn(
            'GREETING = "patched_before_build"',
            pathlib.Path(whl_fg_rloc).read_text(encoding="utf-8"),
        )

        for bare_name in ("sdist_demo_bare_a", "sdist_demo_bare_b"):
            bare_rloc = rf.Rlocation(
                f"rules_python/tests/pypi/py_wheel_library/{bare_name}.sdist_build.whl"
            )
            assert bare_rloc is not None
            self.assertTrue(pathlib.Path(bare_rloc).is_file())

    def test_cross_platform_target_fails_before_build(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            proc = subprocess.run(
                [
                    sys.executable,
                    str(pathlib.Path(sdist_wheel_builder.__file__).resolve()),
                    "--sdist",
                    str(tmp_path / "unused.tar.gz"),
                    "--wheel-dir",
                    str(tmp_path / "out.whldir"),
                    "--target-os",
                    "nonexistent_os",
                ],
                capture_output=True,
                text=True,
                check=False,
                env=_builder_env(),
            )
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn(
                "the default sdist builder only builds for the host",
                proc.stderr,
            )

    def test_mismatched_target_python_version_fails_before_build(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            proc = subprocess.run(
                [
                    sys.executable,
                    str(pathlib.Path(sdist_wheel_builder.__file__).resolve()),
                    "--sdist",
                    str(tmp_path / "unused.tar.gz"),
                    "--wheel-dir",
                    str(tmp_path / "out.whldir"),
                    "--target-python-version",
                    "2.7",
                ],
                capture_output=True,
                text=True,
                check=False,
                env=_builder_env(),
            )
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn(
                "Target Python version (2.7) differs from build Python interpreter",
                proc.stderr,
            )

    def test_bad_pre_build_patch_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            sdist_tar = write_sdist_tar(
                tmp_path / "patch_fail-1.0.tar.gz",
                {
                    "patch_fail-1.0/setup.py": (
                        "from setuptools import setup\n"
                        "setup(name='patch-fail', version='1.0', packages=['patch_fail'])\n"
                    ),
                    "patch_fail-1.0/patch_fail/__init__.py": "X = 1\n",
                },
            )
            bad_patch = tmp_path / "bad.patch"
            bad_patch.write_text(
                "--- a/patch_fail/__init__.py\n"
                "+++ b/patch_fail/__init__.py\n"
                "@@ -1,1 +1,1 @@\n"
                "-DOES_NOT_MATCH = 1\n"
                "+X = 2\n",
                encoding="utf-8",
            )
            proc = subprocess.run(
                [
                    sys.executable,
                    str(pathlib.Path(sdist_wheel_builder.__file__).resolve()),
                    "--sdist",
                    str(sdist_tar),
                    "--wheel-dir",
                    str(tmp_path / "out.whldir"),
                    "--patch",
                    f"{bad_patch}:1",
                ],
                capture_output=True,
                text=True,
                check=False,
                env=_builder_env(),
            )
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("context mismatch", proc.stderr)

    def test_dep_file_conflict_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            fp_a = tmp_path / "src/util/__init__.py"
            fp_b = tmp_path / "bin/util/__init__.py"
            fp_a.parent.mkdir(parents=True, exist_ok=True)
            fp_b.parent.mkdir(parents=True, exist_ok=True)
            fp_a.write_text("A = 1\n", encoding="utf-8")
            fp_b.write_text("B = 2\n", encoding="utf-8")
            with self.assertRaisesRegex(
                ValueError,
                "Conflicting build_deps files map to the same path '_main/util/__init__.py'",
            ):
                sdist_wheel_builder._stage_dep_files(
                    deps_dir=tmp_path / "deps",
                    prefix=tmp_path,
                    workspace_name="_main",
                    import_roots=["_main"],
                    dep_files=[
                        "src/util/__init__.py=util/__init__.py",
                        "bin/util/__init__.py=util/__init__.py",
                    ],
                )

    def test_missing_import_root_fails_and_non_wheel_bin_ignored(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            fp = tmp_path / "external/pypi_foo/site-packages/foo/__init__.py"
            fp.parent.mkdir(parents=True, exist_ok=True)
            fp.write_text("X = 1\n", encoding="utf-8")
            with self.assertRaisesRegex(
                ValueError,
                "Import root 'site-packages' does not exist under staged build_deps",
            ):
                sdist_wheel_builder._stage_dep_files(
                    deps_dir=tmp_path / "deps",
                    prefix=tmp_path,
                    workspace_name="_main",
                    import_roots=["site-packages"],
                    dep_files=[
                        "external/pypi_foo/site-packages/foo/__init__.py=../pypi_foo/site-packages/foo/__init__.py"
                    ],
                )

            non_wheel = tmp_path / "non_wheel_tree"
            (non_wheel / "bin").mkdir(parents=True, exist_ok=True)
            wheel_py, _, bin_dirs = (
                sdist_wheel_builder._resolve_wheel_and_bootstrap_paths(
                    tmp_path, ["non_wheel_tree"], []
                )
            )
            self.assertEqual(wheel_py, [])
            self.assertEqual(bin_dirs, [])


if __name__ == "__main__":
    unittest.main()

"""Regression test for dangling runtime package links in persistent venvs."""

from __future__ import annotations

import os
import pathlib
import tempfile
import unittest

from tests.bootstrap_impls.bootstrap_template_loader import load_bootstrap


def _can_create_symlinks() -> bool:
    with tempfile.TemporaryDirectory() as temp:
        try:
            os.symlink(temp, os.path.join(temp, "link"), target_is_directory=True)
        except OSError:
            return False
    return True


class CachedVenvDanglingSymlinkTest(unittest.TestCase):
    @unittest.skipUnless(_can_create_symlinks(), "can't create symlinks")
    def test_replaces_dangling_package_link_before_creating_child_link(self) -> None:
        self._test_replaces_dangling_package_link(symlinks_supported=True)

    @unittest.skipUnless(os.name == "nt", "junctions are Windows only")
    def test_replaces_dangling_package_junction_before_creating_child_link(
        self,
    ) -> None:
        self._test_replaces_dangling_package_link(symlinks_supported=False)

    @unittest.skipUnless(os.name == "nt", "junctions are Windows only")
    def test_dangling_junction_is_detected_and_removed(self) -> None:
        # The bootstrap relies on these to remove a dangling junction, which
        # islink() doesn't detect.
        import _winapi

        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            target = root / "target"
            target.mkdir()
            junction = root / "junction"
            _winapi.CreateJunction(str(target), str(junction))  # pyrefly: ignore[missing-attribute]
            target.rmdir()

            self.assertFalse(os.path.islink(junction))
            self.assertTrue(os.path.lexists(junction))
            self.assertFalse(os.path.exists(junction))
            os.unlink(junction)
            self.assertFalse(os.path.lexists(junction))

    def _test_replaces_dangling_package_link(self, *, symlinks_supported) -> None:
        bootstrap = load_bootstrap()
        # False uses the fallback for when symlinks can't be created, which
        # creates a junction for a directory.
        bootstrap["_symlinks_supported"] = symlinks_supported
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            runfiles = root / "runfiles"
            old_package = runfiles / "old/annotated_types"
            old_package.mkdir(parents=True)
            (old_package / "__init__.py").touch()
            # The venv isn't run, and Windows can't delete a hard link to the
            # running interpreter, e.g. when cleaning up the temporary
            # directory, so link to a stand-in instead.
            python = root / "python/python.exe"
            python.parent.mkdir()
            python.touch()
            bootstrap.update(
                EXTRACT_ROOT=str(root / "cache"),
                PYTHON_BINARY="_main/_process.venv/Scripts/python.exe",
                PYTHON_BINARY_ACTUAL=str(python),
                RESOLVE_PYTHON_BINARY_AT_RUNTIME=False,
                RUNTIME_VENV_SYMLINKS={
                    "Lib/site-packages/annotated_types": "old/annotated_types",
                },
            )

            bootstrap["_create_venv"](str(runfiles), [])
            old_package.rename(root / "retired-package")

            new_package = runfiles / "new/annotated_types"
            new_package.mkdir(parents=True)
            (new_package / "__init__.py").touch()
            bootstrap["RUNTIME_VENV_SYMLINKS"] = {
                "Lib/site-packages/annotated_types/__init__.py": "new/annotated_types/__init__.py",
            }

            bootstrap["_create_venv"](str(runfiles), [])

            package = (
                root / "cache/_main/_process.venv/Lib/site-packages/annotated_types"
            )
            package_init = package / "__init__.py"
            self.assertTrue(package.is_dir())
            self.assertFalse(package.is_symlink())
            self.assertFalse(getattr(os.path, "isjunction", lambda _: False)(package))
            # The fallback creates a hard link for a file.
            self.assertEqual(package_init.is_symlink(), symlinks_supported)
            self.assertTrue(os.path.samefile(package_init, new_package / "__init__.py"))


if __name__ == "__main__":
    unittest.main()

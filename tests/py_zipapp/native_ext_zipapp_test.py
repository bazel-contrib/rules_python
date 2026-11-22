import os
import posixpath
import subprocess
import unittest
import zipfile

S_IFMT = 0o170000
S_IFLNK = 0o120000


def _is_symlink(info):
    return (info.external_attr >> 16) & S_IFMT == S_IFLNK


class NativeExtZipAppTest(unittest.TestCase):
    def test_zipapp_runnable(self):
        output = subprocess.check_output(
            [os.environ["TEST_ZIPAPP"]], stderr=subprocess.STDOUT
        ).decode("utf-8")
        self.assertIn("native ext:", output)

    @unittest.skipIf(os.name == "nt", "zipapps for Windows store copies")
    def test_venv_shared_library_links_to_packed_file(self):
        # The venv links a pip dep's shared library file by file, as a runfiles
        # symlink into the pip repo. The zipapp stores it as a relative symlink
        # to the copy packed from the pip repo, not as a second copy.
        with zipfile.ZipFile(os.environ["TEST_ZIPAPP"]) as zf:
            namelist = zf.namelist()
            venv_lib = next(
                (
                    name
                    for name in namelist
                    if ".venv/" in name
                    and "/site-packages/markupsafe/_speedups." in name
                    and name.endswith(".so")
                ),
                None,
            )
            self.assertIsNotNone(venv_lib, "\n".join(namelist))
            self.assertTrue(
                _is_symlink(zf.getinfo(venv_lib)), f"{venv_lib} is not a symlink"
            )
            target = posixpath.normpath(
                posixpath.join(
                    posixpath.dirname(venv_lib), zf.read(venv_lib).decode("utf-8")
                )
            )
            self.assertIn(target, namelist)
            self.assertNotIn(".venv/", target)
            self.assertFalse(
                _is_symlink(zf.getinfo(target)), f"{target} should be the packed file"
            )


if __name__ == "__main__":
    unittest.main()

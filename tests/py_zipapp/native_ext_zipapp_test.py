import os
import posixpath
import stat
import subprocess
import unittest
import zipfile


def _is_symlink(info):
    return stat.S_ISLNK(info.external_attr >> 16)


class NativeExtZipAppTest(unittest.TestCase):
    def test_zipapp_runnable(self):
        output = subprocess.check_output([os.environ["TEST_ZIPAPP"]]).decode("utf-8")
        self.assertIn("native ext:", output)

    @unittest.skipIf(os.name == "nt", "zipapps for Windows store copies")
    def test_venv_shared_library_links_to_packed_file(self):
        # The venv links a pip dep's shared library file by file, as a runfiles
        # symlink into the pip repo. The zipapp stores it as a relative symlink
        # to the copy packed from the pip repo, not as a second copy.
        with zipfile.ZipFile(os.environ["TEST_ZIPAPP"]) as zf:
            namelist = zf.namelist()
            venv_lib = None
            for name in namelist:
                if ".venv/" not in name:
                    continue
                if "/site-packages/markupsafe/_speedups." not in name:
                    continue
                if not name.endswith(".so"):
                    continue
                venv_lib = name
                break
            if venv_lib is None:
                self.fail("\n".join(namelist))
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

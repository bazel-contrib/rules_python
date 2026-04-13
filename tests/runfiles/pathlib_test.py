import os
import pathlib
import tempfile
import unittest

from python.runfiles import runfiles


class PathlibTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory(dir=os.environ.get("TEST_TMPDIR"))
        # Runfiles paths are expected to be posix paths internally when we construct the strings for assertions
        self.root_dir = pathlib.Path(self.tmpdir.name).as_posix()

    def tearDown(self) -> None:
        self.tmpdir.cleanup()

    def test_path_api(self) -> None:
        r = runfiles.Create({"RUNFILES_DIR": self.root_dir})
        assert r is not None
        root = r.root()

        # Test basic joining
        p = root / "repo/pkg/file.txt"
        self.assertEqual(str(p), f"{self.root_dir}/repo/pkg/file.txt")

        # Test PurePath API
        self.assertEqual(p.name, "file.txt")
        self.assertEqual(p.suffix, ".txt")
        self.assertEqual(p.parent.name, "pkg")
        self.assertEqual(p.parts, ("repo", "pkg", "file.txt"))
        self.assertEqual(p.stem, "file")
        self.assertEqual(p.suffixes, [".txt"])

        # Test multiple joins
        p2 = root / "repo" / "pkg" / "file.txt"
        self.assertEqual(p, p2)

        # Test joins with pathlib objects
        p3 = root / pathlib.PurePath("repo/pkg/file.txt")
        self.assertEqual(p, p3)

    def test_root(self) -> None:
        r = runfiles.Create({"RUNFILES_DIR": self.root_dir})
        assert r is not None
        self.assertEqual(str(r.root()), self.root_dir)

    def test_runfiles_root_method(self) -> None:
        r = runfiles.Create({"RUNFILES_DIR": self.root_dir})
        assert r is not None
        p = r.root() / "foo/bar"
        self.assertEqual(p.runfiles_root(), r.root())
        self.assertEqual(str(p.runfiles_root()), self.root_dir)

    def test_os_path_like(self) -> None:
        r = runfiles.Create({"RUNFILES_DIR": self.root_dir})
        assert r is not None
        p = r.root() / "foo"
        self.assertEqual(os.fspath(p), f"{self.root_dir}/foo")

    def test_equality_and_hash(self) -> None:
        r = runfiles.Create({"RUNFILES_DIR": self.root_dir})
        assert r is not None
        p1 = r.root() / "foo"
        p2 = r.root() / "foo"
        p3 = r.root() / "bar"

        self.assertEqual(p1, p2)
        self.assertNotEqual(p1, p3)
        self.assertEqual(hash(p1), hash(p2))

    def test_join_path(self) -> None:
        r = runfiles.Create({"RUNFILES_DIR": self.root_dir})
        assert r is not None
        p = r.root().joinpath("repo", "file")
        self.assertEqual(str(p), f"{self.root_dir}/repo/file")

    def test_parents(self) -> None:
        r = runfiles.Create({"RUNFILES_DIR": self.root_dir})
        assert r is not None
        p = r.root() / "a/b/c"
        parents = list(p.parents)
        self.assertEqual(len(parents), 3)
        self.assertEqual(str(parents[0]), f"{self.root_dir}/a/b")
        self.assertEqual(str(parents[1]), f"{self.root_dir}/a")
        self.assertEqual(str(parents[2]), self.root_dir)

    def test_with_methods(self) -> None:
        r = runfiles.Create({"RUNFILES_DIR": self.root_dir})
        assert r is not None
        p = r.root() / "foo/bar.txt"
        self.assertEqual(str(p.with_name("baz.py")), f"{self.root_dir}/foo/baz.py")
        self.assertEqual(str(p.with_suffix(".dat")), f"{self.root_dir}/foo/bar.dat")

    def test_match(self) -> None:
        r = runfiles.Create({"RUNFILES_DIR": self.root_dir})
        assert r is not None
        p = r.root() / "foo/bar.txt"
        self.assertTrue(p.match("*.txt"))
        self.assertTrue(p.match("foo/*.txt"))
        self.assertFalse(p.match("bar/*.txt"))


if __name__ == "__main__":
    unittest.main()

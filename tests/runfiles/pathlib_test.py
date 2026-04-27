import os
import pathlib
import tempfile
import unittest

from python.runfiles import runfiles


class PathlibTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory(dir=os.environ.get("TEST_TMPDIR"))
        # Runfiles paths are expected to be posix paths internally when we
        # construct the strings for assertions
        self.root_path = pathlib.Path(self.tmpdir.name).resolve()
        self.root_dir = self.root_path.as_posix()

        # Create dummy files for I/O tests
        self.repo_dir = self.root_path / "my_repo"
        self.repo_dir.mkdir()
        self.test_file = self.repo_dir / "data.txt"
        self.test_file.write_text("hello runfiles", encoding="utf-8")
        self.sub_dir = self.repo_dir / "subdir"
        self.sub_dir.mkdir()
        (self.sub_dir / "other.txt").write_text("other content", encoding="utf-8")

    def _create_runfiles(self) -> runfiles.Runfiles:
        r = runfiles.Create({"RUNFILES_DIR": self.root_dir})
        assert r is not None
        return r

    def tearDown(self) -> None:
        self.tmpdir.cleanup()

    def test_path_api(self) -> None:
        r = self._create_runfiles()
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
        r = self._create_runfiles()
        self.assertEqual(str(r.root()), self.root_dir)

    def test_runfiles_root_method(self) -> None:
        r = self._create_runfiles()
        p = r.root() / "foo/bar"
        self.assertEqual(p.runfiles_root(), r.root())
        self.assertEqual(str(p.runfiles_root()), self.root_dir)

    def test_os_path_like(self) -> None:
        r = self._create_runfiles()
        p = r.root() / "foo"
        self.assertEqual(os.fspath(p), f"{self.root_dir}/foo")

    def test_equality_and_hash(self) -> None:
        r = self._create_runfiles()
        p1 = r.root() / "foo"
        p2 = r.root() / "foo"
        p3 = r.root() / "bar"

        self.assertEqual(p1, p2)
        self.assertNotEqual(p1, p3)
        self.assertEqual(hash(p1), hash(p2))

    def test_join_path(self) -> None:
        r = self._create_runfiles()
        p = r.root().joinpath("repo", "file")
        self.assertEqual(str(p), f"{self.root_dir}/repo/file")

    def test_parents(self) -> None:
        r = self._create_runfiles()
        p = r.root() / "a/b/c"
        parents = list(p.parents)
        self.assertEqual(len(parents), 3)
        self.assertEqual(str(parents[0]), f"{self.root_dir}/a/b")
        self.assertEqual(str(parents[1]), f"{self.root_dir}/a")
        self.assertEqual(str(parents[2]), self.root_dir)

    def test_with_methods(self) -> None:
        r = self._create_runfiles()
        p = r.root() / "foo/bar.txt"
        self.assertEqual(str(p.with_name("baz.py")), f"{self.root_dir}/foo/baz.py")
        self.assertEqual(str(p.with_suffix(".dat")), f"{self.root_dir}/foo/bar.dat")

    def test_match(self) -> None:
        r = self._create_runfiles()
        p = r.root() / "foo/bar.txt"
        self.assertTrue(p.match("*.txt"))
        self.assertTrue(p.match("foo/*.txt"))
        self.assertFalse(p.match("bar/*.txt"))

    def test_reading_api(self) -> None:
        r = self._create_runfiles()
        root = r.root()
        p = root / "my_repo/data.txt"

        self.assertTrue(p.exists())
        self.assertTrue(p.is_file())
        self.assertEqual(p.read_text(encoding="utf-8"), "hello runfiles")
        self.assertEqual(p.read_bytes(), b"hello runfiles")

        with p.open("r", encoding="utf-8") as f:
            self.assertEqual(f.read(), "hello runfiles")

    def test_stat_api(self) -> None:
        r = self._create_runfiles()
        root = r.root()
        p = root / "my_repo/data.txt"

        st = p.stat()
        self.assertEqual(st.st_size, len("hello runfiles"))

    def test_iteration_api(self) -> None:
        r = self._create_runfiles()
        root = r.root()
        p = root / "my_repo"

        self.assertTrue(p.is_dir())
        contents = {c.name for c in p.iterdir()}
        self.assertEqual(contents, {"data.txt", "subdir"})
        # Ensure they are still runfiles.Path
        for c in p.iterdir():
            self.assertIsInstance(c, runfiles.Path)

    def test_glob(self) -> None:
        r = self._create_runfiles()
        root = r.root()
        p = root / "my_repo"

        glob_results = {
            pathlib.PurePath(c).relative_to(pathlib.PurePath(p)).as_posix()
            for c in p.glob("*.txt")
        }
        self.assertEqual(glob_results, {"data.txt"})

        rglob_results = {
            pathlib.PurePath(c).relative_to(pathlib.PurePath(p)).as_posix()
            for c in p.rglob("*.txt")
        }
        self.assertEqual(rglob_results, {"data.txt", "subdir/other.txt"})

        for c in p.rglob("*.txt"):
            self.assertIsInstance(c, runfiles.Path)

    def test_resolve_and_absolute(self) -> None:
        r = self._create_runfiles()
        root = r.root()
        p = root / "my_repo/data.txt"

        resolved = p.resolve()
        self.assertIsInstance(resolved, runfiles.Path)
        self.assertTrue(resolved.exists())
        self.assertEqual(resolved.read_text(encoding="utf-8"), "hello runfiles")

        absoluted = p.absolute()
        self.assertIsInstance(absoluted, runfiles.Path)
        self.assertTrue(absoluted.exists())
        self.assertEqual(absoluted.read_text(encoding="utf-8"), "hello runfiles")

    def test_runfile_path(self) -> None:
        r = self._create_runfiles()
        root = r.root()
        p = root / "my_repo/data.txt"
        self.assertEqual(p.runfile_path, "my_repo/data.txt")

        p2 = root / "foo" / "bar.txt"
        self.assertEqual(p2.runfile_path, "foo/bar.txt")

        self.assertEqual(root.runfile_path, "")
        self.assertEqual(repr(root), "runfiles.Path('')")
        self.assertEqual(repr(p), "runfiles.Path('my_repo/data.txt')")


if __name__ == "__main__":
    unittest.main()

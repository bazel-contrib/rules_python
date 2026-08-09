import pathlib
import shutil
import stat
import tempfile

from absl.testing import absltest
from sphinxdocs.private.sphinx_build import DirectorySyncer, DirectorySyncerError


class DirectorySyncerTest(absltest.TestCase):
    def setUp(self):
        super().setUp()
        self.test_dir = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.test_dir, ignore_errors=True)
        self.srcdir = self.test_dir / "src"
        self.destdir = self.test_dir / "dest"
        self.srcdir.mkdir()

    def _write_src(self, rel_path, content, mode=None):
        path = self.srcdir / rel_path
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists():
            path.chmod(stat.S_IRUSR | stat.S_IWUSR | stat.S_IRGRP | stat.S_IROTH)
        path.write_text(content)
        if mode is not None:
            path.chmod(mode)
        return path

    def assert_dest_equals(self, rel_path, expected_content):
        dest_file = self.destdir / rel_path
        self.assertTrue(dest_file.exists(), f"Expected {dest_file} to exist")
        self.assertEqual(expected_content, dest_file.read_text())

    def assert_dest_not_exists(self, rel_path):
        dest_file = self.destdir / rel_path
        self.assertFalse(dest_file.exists(), f"Expected {dest_file} to not exist")

    def test_copytree(self):
        self._write_src("file1.txt", "hello")
        self._write_src("sub/file2.txt", "world")

        syncer = DirectorySyncer(self.srcdir, self.destdir)
        syncer.copytree()

        self.assert_dest_equals("file1.txt", "hello")
        self.assert_dest_equals("sub/file2.txt", "world")

    def test_sync_initial_and_incremental(self):
        self._write_src("doc1.md", "v1")
        self._write_src("doc2.md", "v1")
        self._write_src("doc3.md", "v1")

        syncer = DirectorySyncer(self.srcdir, self.destdir)
        # Initial sync
        syncer.sync(
            {
                "doc1.md": "sha-doc1-v1",
                "doc2.md": "sha-doc2-v1",
                "doc3.md": "sha-doc3-v1",
            }
        )

        self.assert_dest_equals("doc1.md", "v1")
        self.assert_dest_equals("doc2.md", "v1")
        self.assert_dest_equals("doc3.md", "v1")

        # Incremental sync:
        # - doc1.md: unchanged SHA
        # - doc2.md: updated SHA & content
        # - doc3.md: removed from entries
        # - doc4.md: newly created file
        self._write_src("doc2.md", "v2")
        self._write_src("doc4.md", "v1")

        syncer.sync(
            {
                "doc1.md": "sha-doc1-v1",
                "doc2.md": "sha-doc2-v2",
                "doc4.md": "sha-doc4-v1",
            }
        )

        self.assert_dest_equals("doc1.md", "v1")
        self.assert_dest_equals("doc2.md", "v2")
        self.assert_dest_not_exists("doc3.md")
        self.assert_dest_equals("doc4.md", "v1")

    def test_read_only_file_becomes_writable(self):
        read_only_mode = stat.S_IRUSR | stat.S_IRGRP | stat.S_IROTH
        self._write_src("readonly.txt", "version 1", mode=read_only_mode)
        syncer = DirectorySyncer(self.srcdir, self.destdir)
        syncer.sync({"readonly.txt": "sha-v1"})

        dest_file = self.destdir / "readonly.txt"
        self.assert_dest_equals("readonly.txt", "version 1")
        self.assertTrue(
            dest_file.stat().st_mode & stat.S_IWUSR,
            "Destination file should be writable",
        )

        # Ensure subsequent incremental updates can overwrite the file without permission error
        self._write_src("readonly.txt", "version 2", mode=read_only_mode)
        syncer.sync({"readonly.txt": "sha-v2"})
        self.assert_dest_equals("readonly.txt", "version 2")

    def test_sync_directory_artifact(self):
        dir_artifact = self.srcdir / "tree_art"
        dir_artifact.mkdir()
        (dir_artifact / "page.md").write_text("content")

        syncer = DirectorySyncer(self.srcdir, self.destdir)
        syncer.sync(
            {
                "tree_art": "sha-dir-art",
            }
        )

        self.assert_dest_equals("tree_art/page.md", "content")

    def test_errors_bubble_up(self):
        syncer = DirectorySyncer(self.srcdir, self.destdir)
        with self.assertRaises(DirectorySyncerError) as cm:
            syncer.sync(
                {
                    "non_existent_1.txt": "sha1",
                    "non_existent_2.txt": "sha2",
                }
            )
        self.assertGreaterEqual(len(cm.exception.errors), 2)


if __name__ == "__main__":
    absltest.main()

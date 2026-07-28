import unittest

from integration_tests import runner


class PersistentWorkerTest(runner.TestCase):
    def _check_index_html(self, text: str, should_exist: bool):
        index_html = (
            self.repo_root / "bazel-bin" / "docs" / "_build" / "html" / "index.html"
        )
        if not index_html.exists():
            self.fail(f"Could not find index.html at {index_html}")
        content = index_html.read_text()
        if should_exist:
            self.assertIn(
                text,
                content,
                f"Expected '{text}' in index.html after build, but not found.",
            )
        else:
            self.assertNotIn(
                text,
                content,
                f"Expected '{text}' NOT to be in index.html after build, but found it.",
            )

    def test_incremental_add_and_remove_files(self):
        # 1. Initial build
        result = self.run_bazel("build", "//:docs")
        self.assert_result_matches(result, "bazel-bin")
        index_html = (
            self.repo_root / "bazel-bin" / "docs" / "_build" / "html" / "index.html"
        )
        self.assertTrue(
            index_html.exists(), "index.html should exist after initial build"
        )

        # 2. Add a new markdown file and verify it is included across incremental build
        page2_md = self.repo_root / "page2.md"
        page2_md.write_text("# Page 2\n\nThis is a newly added page.\n")
        result = self.run_bazel("build", "//:docs")
        self.assert_result_matches(result, "bazel-bin")
        self._check_index_html("page2.html", should_exist=True)

        # 3. Remove the added markdown file and verify the persistent worker cleans up
        # stale source files and invalidates toctrees without errors or warnings.
        page2_md.unlink()
        result = self.run_bazel("build", "//:docs")
        self.assert_result_matches(result, "bazel-bin")
        self._check_index_html("page2.html", should_exist=False)


if __name__ == "__main__":
    unittest.main()

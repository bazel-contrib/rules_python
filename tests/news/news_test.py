import pathlib
import unittest

from python.runfiles import runfiles


def _get_news_dir():
    rf = runfiles.Create()
    path = rf.Rlocation("rules_python/news")
    if path:
        return pathlib.Path(path)
    return None


class NewsTest(unittest.TestCase):
    def test_all_news_files_are_valid(self):
        news_dir = _get_news_dir()
        self.assertIsNotNone(news_dir, "Could not locate news directory in runfiles")
        self.assertTrue(news_dir.exists(), "News directory does not exist in runfiles")

        allowed_categories = {"added", "changed", "fixed", "removed"}

        for p in news_dir.iterdir():
            if not p.is_file():
                continue
            # Ignore BUILD files and .gitkeep if they are in the directory
            if p.name in ("BUILD", "BUILD.bazel", ".gitkeep"):
                continue

            filename = p.name

            # Collapse extension and filename check into a single assertRegex
            self.assertRegex(
                filename,
                r"^[^.]+\.[^.]+\.md$",
                f"News filename {filename} must follow <id>.<category>.md pattern",
            )

            parts = filename.split(".")
            category = parts[1].lower()

            # Category must be valid
            self.assertIn(
                category,
                allowed_categories,
                f"News file {filename} has invalid category '{category}'. "
                f"Must be one of {allowed_categories}",
            )

            # Must be readable as UTF-8
            try:
                content = p.read_text(encoding="utf-8").strip()
            except (IOError, UnicodeDecodeError) as e:
                self.fail(f"Failed to read news file {filename} as UTF-8: {e}")

            # Content must not be empty
            self.assertTrue(len(content) > 0, f"News file {filename} must not be empty")

            # Content must NOT start with bullet points (* or -)
            self.assertFalse(
                content.startswith("* ") or content.startswith("- "),
                f"News file {filename} must not start with bullet points (* or -). "
                "The release tool adds them automatically.",
            )


if __name__ == "__main__":
    unittest.main()

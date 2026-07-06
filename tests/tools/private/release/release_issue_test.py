import unittest

from tools.private.release.release_issue import (
    add_backports_to_body,
    add_sync_changelog_task_to_body,
    format_metadata_line,
    parse_checklist_state,
    parse_metadata_line,
)


class ReleaseIssueTest(unittest.TestCase):
    def test_parse_metadata_line_spaces(self):
        # Test with spaces around '='
        line = "- [ ] Tag Final | tag = 2.0.0 commit = abcdef12"
        expected = {
            "checked": False,
            "name": "Tag Final",
            "metadata": {"tag": "2.0.0", "commit": "abcdef12"},
            "original_line": line,
        }
        self.assertEqual(parse_metadata_line(line), expected)

        # Test with spaces after '='
        line = "- [ ] Tag Final | tag= 2.0.0 commit= abcdef12"
        expected = {
            "checked": False,
            "name": "Tag Final",
            "metadata": {"tag": "2.0.0", "commit": "abcdef12"},
            "original_line": line,
        }
        self.assertEqual(parse_metadata_line(line), expected)

        # Test with standard format (no spaces)
        line = "- [ ] Tag Final | tag=2.0.0 commit=abcdef12"
        expected = {
            "checked": False,
            "name": "Tag Final",
            "metadata": {"tag": "2.0.0", "commit": "abcdef12"},
            "original_line": line,
        }
        self.assertEqual(parse_metadata_line(line), expected)

        # Test with no metadata
        line = "- [ ] Tag Final"
        expected = {
            "checked": False,
            "name": "Tag Final",
            "metadata": {},
            "original_line": line,
        }
        self.assertEqual(parse_metadata_line(line), expected)

    def test_format_metadata_line(self):
        # Test with commit metadata (should have space)
        metadata = {"status": "done", "tag": "2.0.0", "commit": "abcdef12"}
        expected = "- [x] Tag Final | status=done tag=2.0.0 commit= abcdef12"
        self.assertEqual(format_metadata_line(True, "Tag Final", metadata), expected)

        # Test with other metadata (should not have space)
        metadata = {"status": "done", "pr": "#122"}
        expected = "- [x] Prepare Release | status=done pr=#122"
        self.assertEqual(
            format_metadata_line(True, "Prepare Release", metadata), expected
        )

        # Test with no metadata
        expected = "- [ ] Tag Final"
        self.assertEqual(format_metadata_line(False, "Tag Final", {}), expected)

    def test_add_backports_to_body(self):
        body = """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch
- [ ] Tag Final

## Backports
- [ ] #123 | status=done
"""
        items = [
            {"ref": "124"},
            {"ref": "#124"},
            {"ref": "125"},
            {"ref": "#123"},
        ]
        updated_body = add_backports_to_body(body, items)
        expected_body = """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch
- [ ] Tag Final

## Backports
- [ ] #123 | status=done
- [ ] #124
- [ ] #125
"""
        self.assertEqual(updated_body.strip(), expected_body.strip())

    def test_add_sync_changelog_task_to_body(self):
        body = """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch
- [ ] Tag Final
"""
        # Insert first task (should go before Tag Final)
        body = add_sync_changelog_task_to_body(body, 124)
        expected = """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch
- [ ] Sync Changelog #124
- [ ] Tag Final
"""
        self.assertEqual(body.strip(), expected.strip())

        # Insert second task (should go after the last Sync Changelog task)
        body = add_sync_changelog_task_to_body(body, 125)
        expected = """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch
- [ ] Sync Changelog #124
- [ ] Sync Changelog #125
- [ ] Tag Final
"""
        self.assertEqual(body.strip(), expected.strip())

        # Insert duplicate (should be ignored)
        body = add_sync_changelog_task_to_body(body, 124)
        self.assertEqual(body.strip(), expected.strip())

    def test_parse_checklist_state_with_sync_changelogs(self):
        body = """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0
- [ ] Sync Changelog #124 | status=pending pr=#125
- [ ] Sync Changelog #126
- [ ] Tag Final
"""
        state = parse_checklist_state(body)
        self.assertIn(124, state["sync_changelogs"])
        self.assertIn(126, state["sync_changelogs"])

        task_124 = state["sync_changelogs"][124]
        self.assertEqual(task_124.name, "Sync Changelog #124")
        self.assertFalse(task_124.checked)
        self.assertEqual(task_124.status, "pending")
        self.assertEqual(task_124.pr, "#125")

        task_126 = state["sync_changelogs"][126]
        self.assertEqual(task_126.name, "Sync Changelog #126")
        self.assertFalse(task_126.checked)
        self.assertIsNone(task_126.status)
        self.assertIsNone(task_126.pr)


if __name__ == "__main__":
    unittest.main()

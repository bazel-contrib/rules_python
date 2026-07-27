import argparse

from tools.private.release.complete_sync_changelog import CompleteSyncChangelog

pytest_plugins = ["tests.tools.private.release.release_test_helper"]


def test_complete_sync_changelog_success(mock_gh):
    args = argparse.Namespace(pr=999)
    mock_gh.prs[999] = {
        "state": "MERGED",
        "body": "Updates CHANGELOG.md\n\nRelease-Tracking-Issue: #123",
        "mergeCommit": {"oid": "abcdef1234567890"},
    }
    issue_body = """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch
- [ ] Sync Changelog #124 | status=pending pr=#999
- [ ] Sync Changelog #125 | status=pending pr=#999
- [ ] Sync Changelog #126 | status=pending pr=#888
- [ ] Tag Final

## Backports
"""
    mock_gh.issues[123] = {
        "title": "Release 2.1.0",
        "body": issue_body,
        "labels": ["type: release"],
        "number": 123,
        "url": "https://github.com/bazel-contrib/rules_python/issues/123",
    }

    result = CompleteSyncChangelog(args, mock_gh).run()

    assert result == 0
    updated_body = mock_gh.get_issue_body(123)

    # Check that only tasks pointing to #999 were marked checked=True and status=done
    assert (
        "- [x] Sync Changelog #124 | status=done pr=#999 commit= abcdef12"
        in updated_body
    )
    assert (
        "- [x] Sync Changelog #125 | status=done pr=#999 commit= abcdef12"
        in updated_body
    )
    # Task pointing to #888 should remain unchanged
    assert "- [ ] Sync Changelog #126 | status=pending pr=#888" in updated_body


def test_complete_sync_changelog_not_merged(mock_gh):
    args = argparse.Namespace(pr=999)
    mock_gh.prs[999] = {
        "state": "OPEN",
        "body": "Updates CHANGELOG.md\n\nRelease-Tracking-Issue: #123",
    }

    result = CompleteSyncChangelog(args, mock_gh).run()

    assert result == 1


def test_complete_sync_changelog_missing_tracking_issue_link(mock_gh):
    args = argparse.Namespace(pr=999)
    mock_gh.prs[999] = {
        "state": "MERGED",
        "body": "Updates CHANGELOG.md without tracking issue link",
        "mergeCommit": {"oid": "abcdef1234567890"},
    }

    result = CompleteSyncChangelog(args, mock_gh).run()

    assert result == 1


def test_complete_sync_changelog_no_matching_tasks(mock_gh):
    args = argparse.Namespace(pr=999)
    mock_gh.prs[999] = {
        "state": "MERGED",
        "body": "Updates CHANGELOG.md\n\nRelease-Tracking-Issue: #123",
        "mergeCommit": {"oid": "abcdef1234567890"},
    }
    # Checklist has no tasks pointing to #999
    issue_body = """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch
- [ ] Sync Changelog #124 | status=pending pr=#888
- [ ] Tag Final

## Backports
"""
    mock_gh.issues[123] = {
        "title": "Release 2.1.0",
        "body": issue_body,
        "labels": ["type: release"],
        "number": 123,
        "url": "https://github.com/bazel-contrib/rules_python/issues/123",
    }

    result = CompleteSyncChangelog(args, mock_gh).run()

    assert result == 0
    assert mock_gh.get_issue_body(123) == issue_body

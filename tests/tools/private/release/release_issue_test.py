from tools.private.release.release_issue import (
    add_backports_to_body,
    add_sync_changelog_task_to_body,
    format_metadata_line,
    parse_checklist_state,
    parse_metadata_line,
)


def test_parse_metadata_line_spaces():
    # Test with spaces around '='
    line = "- [ ] Tag Final | tag = 2.0.0 commit = abcdef12"
    expected = {
        "checked": False,
        "name": "Tag Final",
        "metadata": {"tag": "2.0.0", "commit": "abcdef12"},
        "original_line": line,
    }
    assert parse_metadata_line(line) == expected

    # Test with spaces after '='
    line = "- [ ] Tag Final | tag= 2.0.0 commit= abcdef12"
    expected = {
        "checked": False,
        "name": "Tag Final",
        "metadata": {"tag": "2.0.0", "commit": "abcdef12"},
        "original_line": line,
    }
    assert parse_metadata_line(line) == expected

    # Test with standard format (no spaces)
    line = "- [ ] Tag Final | tag=2.0.0 commit=abcdef12"
    expected = {
        "checked": False,
        "name": "Tag Final",
        "metadata": {"tag": "2.0.0", "commit": "abcdef12"},
        "original_line": line,
    }
    assert parse_metadata_line(line) == expected

    # Test with no metadata
    line = "- [ ] Tag Final"
    expected = {
        "checked": False,
        "name": "Tag Final",
        "metadata": {},
        "original_line": line,
    }
    assert parse_metadata_line(line) == expected


def test_format_metadata_line():
    # Test with commit metadata (should have space)
    metadata = {"status": "done", "tag": "2.0.0", "commit": "abcdef12"}
    expected = "- [x] Tag Final | status=done tag=2.0.0 commit= abcdef12"
    assert format_metadata_line(True, "Tag Final", metadata) == expected

    # Test with other metadata (should not have space)
    metadata = {"status": "done", "pr": "#122"}
    expected = "- [x] Prepare Release | status=done pr=#122"
    assert format_metadata_line(True, "Prepare Release", metadata) == expected

    # Test with no metadata
    expected = "- [ ] Tag Final"
    assert format_metadata_line(False, "Tag Final", {}) == expected


def test_add_backports_to_body():
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
    assert updated_body.strip() == expected_body.strip()


def test_add_sync_changelog_task_to_body():
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
    assert body.strip() == expected.strip()

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
    assert body.strip() == expected.strip()

    # Insert duplicate (should be ignored)
    body = add_sync_changelog_task_to_body(body, 124)
    assert body.strip() == expected.strip()


def test_parse_checklist_state_with_sync_changelogs():
    body = """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0
- [ ] Sync Changelog #124 | status=pending pr=#125
- [ ] Sync Changelog #126
- [ ] Tag Final
"""
    state = parse_checklist_state(body)
    assert 124 in state["sync_changelogs"]
    assert 126 in state["sync_changelogs"]

    task_124 = state["sync_changelogs"][124]
    assert task_124.name == "Sync Changelog #124"
    assert not task_124.checked
    assert task_124.status == "pending"
    assert task_124.pr == "#125"

    task_126 = state["sync_changelogs"][126]
    assert task_126.name == "Sync Changelog #126"
    assert not task_126.checked
    assert task_126.status is None
    assert task_126.pr is None

import argparse

from tools.private.release.add_backports import AddBackports

pytest_plugins = ["tests.tools.private.release.release_test_helper"]


def test_add_backports_explicit_issue(mock_gh):
    args = argparse.Namespace(issue=123, prs=["124", "125"])
    mock_gh.issues[123] = {
        "title": "Release 2.1.0",
        "body": """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch
- [ ] Tag Final

## Backports
""",
        "labels": ["type: release"],
        "number": 123,
        "url": "https://github.com/bazel-contrib/rules_python/issues/123",
    }
    result = AddBackports(args, mock_gh).run()

    assert result == 0
    updated_body = mock_gh.get_issue_body(123)
    assert "- [ ] #124" in updated_body
    assert "- [ ] #125" in updated_body
    assert "- [ ] Tag RC0" in updated_body
    assert "- [ ] Sync Changelog #124" in updated_body
    assert "- [ ] Sync Changelog #125" in updated_body


def test_add_backports_auto_discover_success(mock_gh):
    args = argparse.Namespace(issue=None, prs=["124"])
    issue_num = mock_gh.create_issue(
        title="Release 2.1.0",
        body="""
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch
- [ ] Tag Final

## Backports
""",
        labels=["type: release"],
    )
    result = AddBackports(args, mock_gh).run()

    assert result == 0
    updated_body = mock_gh.get_issue_body(issue_num)
    assert "- [ ] #124" in updated_body


def test_add_backports_auto_discover_no_issues(mock_gh):
    args = argparse.Namespace(issue=None, prs=["124"])

    result = AddBackports(args, mock_gh).run()

    assert result == 1


def test_add_backports_auto_discover_multiple_issues(mock_gh):
    args = argparse.Namespace(issue=None, prs=["124"])
    mock_gh.create_issue(
        title="Release 2.1.0", body="## Backports\n", labels=["type: release"]
    )
    mock_gh.create_issue(
        title="Release 2.2.0", body="## Backports\n", labels=["type: release"]
    )

    result = AddBackports(args, mock_gh).run()

    assert result == 1


def test_add_backports_no_auto_add_rc_if_pending(mock_gh):
    args = argparse.Namespace(issue=123, prs=["124"])
    mock_gh.issues[123] = {
        "title": "Release 2.1.0",
        "body": """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch
- [ ] Tag RC0
- [ ] Tag Final

## Backports
""",
        "labels": ["type: release"],
        "number": 123,
        "url": "https://github.com/bazel-contrib/rules_python/issues/123",
    }
    result = AddBackports(args, mock_gh).run()

    assert result == 0
    updated_body = mock_gh.get_issue_body(123)
    assert "Tag RC1" not in updated_body
    assert "- [ ] Tag RC0" in updated_body
    assert "- [ ] Sync Changelog #124" in updated_body

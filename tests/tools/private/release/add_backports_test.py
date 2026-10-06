import argparse

from dev.release.add_backports import AddBackports

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


def test_add_backports_auto_discover_no_issues_creates_patch_release(
    mock_gh, mock_git, release_tool_env
):
    mock_git.get_tags.return_value = ["1.0.0", "1.2.0"]
    mock_git.get_current_branch.return_value = "main"

    args = argparse.Namespace(issue=None, prs=["124"])

    result = AddBackports(args, mock_gh, mock_git).run()

    assert result == 0
    open_issues = mock_gh.get_open_tracking_issues()
    assert len(open_issues) == 1
    issue = open_issues[0]
    assert issue["title"] == "Release 1.2.1"
    body = issue["body"]
    assert "- [ ] #124" in body
    assert "- [ ] Sync Changelog #124" in body
    assert "Tag RC" not in body
    assert "Prepare Release" not in body
    assert "Create Release branch" not in body
    assert "- [ ] Tag Final" in body


def test_add_backports_auto_discover_skips_complete_release_creates_patch_release(
    mock_gh, mock_git, release_tool_env
):
    # 1.2.1 has already been tagged (Tag Final done) but the issue was never
    # closed. It must be left alone and a new 1.2.2 issue created instead.
    mock_git.get_tags.return_value = ["1.2.0", "1.2.1"]
    mock_git.get_current_branch.return_value = "main"
    complete_body = """
## Checklist
- [x] Sync Changelog #100 | status=done
- [x] Tag Final | status=done tag=1.2.1 commit= abcdef12

## Backports
- [x] #100 | status=done
"""
    complete_issue_num = mock_gh.create_issue(
        title="Release 1.2.1",
        body=complete_body,
        labels=["type: release"],
    )

    args = argparse.Namespace(issue=None, prs=["124"])

    result = AddBackports(args, mock_gh, mock_git).run()

    assert result == 0
    # The completed issue is untouched.
    assert mock_gh.get_issue_body(complete_issue_num) == complete_body

    open_issues = mock_gh.get_open_tracking_issues()
    assert len(open_issues) == 2
    new_issue = next(i for i in open_issues if i["number"] != complete_issue_num)
    assert new_issue["title"] == "Release 1.2.2"
    body = new_issue["body"]
    assert "- [ ] #124" in body
    assert "- [ ] Sync Changelog #124" in body
    assert "- [ ] Tag Final" in body


def test_add_backports_auto_discover_ignores_complete_release_among_multiple(
    mock_gh,
):
    # A stale-but-complete issue alongside an active one should not cause the
    # "multiple open issues" error; the active one is used.
    complete_issue_num = mock_gh.create_issue(
        title="Release 1.2.1",
        body="""
## Checklist
- [x] Tag Final | status=done tag=1.2.1 commit= abcdef12

## Backports
""",
        labels=["type: release"],
    )
    active_issue_num = mock_gh.create_issue(
        title="Release 1.3.0",
        body="""
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch
- [ ] Tag Final

## Backports
""",
        labels=["type: release"],
    )

    args = argparse.Namespace(issue=None, prs=["124"])

    result = AddBackports(args, mock_gh).run()

    assert result == 0
    assert "#124" not in mock_gh.get_issue_body(complete_issue_num)
    active_body = mock_gh.get_issue_body(active_issue_num)
    assert "- [ ] #124" in active_body
    assert "- [ ] Sync Changelog #124" in active_body


def test_add_backports_patch_release_no_rc_added(mock_gh):
    args = argparse.Namespace(issue=123, prs=["124"])
    mock_gh.issues[123] = {
        "title": "Release 1.2.1",
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
    assert "- [ ] Sync Changelog #124" in updated_body
    assert "Tag RC" not in updated_body


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

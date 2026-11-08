import argparse

from dev.release.create_release_issue import CreateReleaseIssue

pytest_plugins = ["tests.tools.private.release.release_test_helper"]


def test_create_release_issue_blocked_by_active_release(mock_gh):
    args = argparse.Namespace(version="2.1.0")
    mock_gh.create_issue(
        title="Release 2.0.0",
        body="""
## Checklist
- [x] Prepare Release | status=done
- [ ] Tag Final
""",
        labels=["type: release"],
    )

    result = CreateReleaseIssue(args, mock_gh).run()

    assert result == 1
    assert [i["title"] for i in mock_gh.issues.values()] == ["Release 2.0.0"]


def test_create_release_issue_ignores_complete_release(mock_gh, release_tool_env):
    # A tagged-but-unclosed release issue must not block the next release.
    args = argparse.Namespace(version="2.1.0")
    complete_body = "- [x] Tag Final | status=done tag=2.0.0 commit= abcdef12\n"
    complete_issue_num = mock_gh.create_issue(
        title="Release 2.0.0",
        body=complete_body,
        labels=["type: release"],
    )

    result = CreateReleaseIssue(args, mock_gh).run()

    assert result == 0
    assert mock_gh.get_issue_body(complete_issue_num) == complete_body
    titles = sorted(i["title"] for i in mock_gh.issues.values())
    assert titles == ["Release 2.0.0", "Release 2.1.0"]
    new_issue = next(
        i for i in mock_gh.issues.values() if i["title"] == "Release 2.1.0"
    )
    assert "- [ ] Tag Final" in new_issue["body"]
    assert "type: release" in new_issue["labels"]


def test_create_release_issue_no_open_issues(mock_gh, release_tool_env):
    args = argparse.Namespace(version="2.1.0")

    result = CreateReleaseIssue(args, mock_gh).run()

    assert result == 0
    assert [i["title"] for i in mock_gh.issues.values()] == ["Release 2.1.0"]

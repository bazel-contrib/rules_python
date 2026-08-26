import argparse

from tools.private.release.complete_prepare import CompletePrepare

pytest_plugins = ["tests.tools.private.release.release_test_helper"]


def test_complete_prepare_with_pr_success(mock_gh):
    args = argparse.Namespace(pr=456, issue=None)
    mock_gh.prs[456] = {
        "state": "MERGED",
        "body": "Prepare release for v2.0.0\n\nWork towards #123",
        "mergeCommit": {"oid": "abcdef1234567890"},
    }
    issue_body = """
## Checklist
- [ ] Prepare Release | status=pending pr=#456
- [ ] Create Release branch
- [ ] Tag Final
"""
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": issue_body,
        "labels": ["type: release"],
        "number": 123,
        "url": "https://github.com/bazel-contrib/rules_python/issues/123",
    }

    result = CompletePrepare(args, mock_gh).run()

    assert result == 0
    updated_body = mock_gh.get_issue_body(123)
    assert (
        "- [x] Prepare Release | status=done pr=#456 commit= abcdef12" in updated_body
    )


def test_complete_prepare_writes_github_output(release_tool_env, mock_gh):
    args = argparse.Namespace(pr=456, issue=None)
    mock_gh.prs[456] = {
        "state": "MERGED",
        "body": "Prepare release for v2.0.0\n\nWork towards #123",
        "mergeCommit": {"oid": "abcdef1234567890"},
    }
    issue_body = """
## Checklist
- [ ] Prepare Release | status=pending pr=#456
- [ ] Create Release branch
- [ ] Tag Final
"""
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": issue_body,
        "labels": ["type: release"],
        "number": 123,
        "url": "https://github.com/bazel-contrib/rules_python/issues/123",
    }

    result = CompletePrepare(args, mock_gh).run()
    assert result == 0
    assert release_tool_env.github_output_file.exists()
    assert (
        release_tool_env.github_output_file.read_text(encoding="utf-8") == "issue=123\n"
    )


def test_complete_prepare_with_issue_success(mock_gh):
    args = argparse.Namespace(pr=None, issue=123)
    mock_gh.prs[456] = {
        "state": "MERGED",
        "body": "Prepare release for v2.0.0",
        "mergeCommit": {"oid": "1234567890abcdef"},
    }
    issue_body = """
## Checklist
- [ ] Prepare Release | status=pending pr=#456
- [ ] Create Release branch
- [ ] Tag Final
"""
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": issue_body,
        "labels": ["type: release"],
        "number": 123,
        "url": "https://github.com/bazel-contrib/rules_python/issues/123",
    }

    result = CompletePrepare(args, mock_gh).run()

    assert result == 0
    updated_body = mock_gh.get_issue_body(123)
    assert (
        "- [x] Prepare Release | status=done pr=#456 commit= 12345678" in updated_body
    )


def test_complete_prepare_no_args(mock_gh):
    args = argparse.Namespace(pr=None, issue=None)
    result = CompletePrepare(args, mock_gh).run()
    assert result == 1


def test_complete_prepare_not_merged(mock_gh):
    args = argparse.Namespace(pr=456, issue=123)
    mock_gh.prs[456] = {
        "state": "OPEN",
        "body": "Prepare release for v2.0.0",
    }
    issue_body = """
## Checklist
- [ ] Prepare Release | status=pending pr=#456
"""
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": issue_body,
        "labels": ["type: release"],
        "number": 123,
    }

    result = CompletePrepare(args, mock_gh).run()
    assert result == 1


def test_complete_prepare_issue_missing_pr_task(mock_gh):
    args = argparse.Namespace(pr=None, issue=123)
    issue_body = """
## Checklist
- [ ] Create Release branch
"""
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": issue_body,
        "labels": ["type: release"],
        "number": 123,
    }

    result = CompletePrepare(args, mock_gh).run()
    assert result == 1

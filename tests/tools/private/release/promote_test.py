import argparse
from pathlib import Path
from unittest.mock import call, patch

from tools.private.release.promote import Promote

pytest_plugins = ["tests.tools.private.release.release_test_helper"]


def test_promote_rc_success(mock_git, mock_gh):
    # Arrange
    issue_num = mock_gh.create_issue(
        title="Release 2.0.0",
        body="- [ ] Tag Final",
        labels=["type: release"],
    )
    args = argparse.Namespace(
        version="2.0.0", issue=issue_num, dry_run=False, remote="my-remote"
    )
    mock_git.get_remote_tags.return_value = ["2.0.0-rc0", "2.0.0-rc1"]
    mock_git.get_commit_sha.return_value = "abcdef123456"
    mock_git.tag_exists.return_value = False

    # Act
    result = Promote(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    mock_git.fetch.assert_has_calls(
        [
            call("my-remote", tags=True, force=True),
            call("my-remote", refspec="release/2.0"),
        ]
    )
    mock_git.get_commit_sha.assert_has_calls(
        [call("2.0.0-rc1"), call("my-remote/release/2.0")]
    )
    mock_git.checkout.assert_not_called()
    mock_git.tag_exists.assert_called_once_with("2.0.0")
    mock_git.tag.assert_called_once_with("2.0.0", "abcdef123456")
    mock_git.push.assert_called_once_with("my-remote", "2.0.0")

    # Verify issue update
    expected_updated_body = "- [x] Tag Final | status=done tag=2.0.0 commit= abcdef12"
    assert mock_gh.get_issue_body(issue_num) == expected_updated_body

    expected_comment = (
        "**New Release Tagged!** 🐍🌿\n\n"
        "Version **2.0.0** has been successfully generated and tagged on branch [`release/2.0`](https://github.com/bazel-contrib/rules_python/tree/release/2.0).\n\n"
        "- [Github Release 2.0.0](https://github.com/bazel-contrib/rules_python/releases/tag/2.0.0)\n"
        "- [BCR Entry 2.0.0](https://registry.bazel.build/modules/rules_python/2.0.0)\n"
        "- [BCR PRs](https://github.com/bazelbuild/bazel-central-registry/pulls?q=is%3Apr%20%28%22bazel-contrib/rules_python%22%20in%3Atitle%29%20%28%22%402.0.0%22%20in%3Atitle%29)\n"
        "- [Release workflow status](https://github.com/bazel-contrib/rules_python/actions/workflows/release_promote.yaml)"
    )
    assert mock_gh.issue_comments[issue_num] == [expected_comment]


def test_promote_rc_writes_github_output(tmp_path, monkeypatch, mock_git, mock_gh):
    # Arrange
    github_output_path = str(tmp_path / "github_output")
    monkeypatch.setenv("GITHUB_OUTPUT", github_output_path)
    issue_num = mock_gh.create_issue(
        title="Release 2.0.0",
        body="- [ ] Tag Final",
        labels=["type: release"],
    )
    args = argparse.Namespace(
        version="2.0.0", issue=issue_num, dry_run=False, remote="my-remote"
    )
    mock_git.get_remote_tags.return_value = ["2.0.0-rc0", "2.0.0-rc1"]
    mock_git.get_commit_sha.return_value = "abcdef123456"
    mock_git.tag_exists.return_value = False

    # Act
    result = Promote(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    assert Path(github_output_path).exists()
    content = Path(github_output_path).read_text(encoding="utf-8")
    assert content == "version=2.0.0\n"


def test_promote_rc_resolve_issue_success(mock_git, mock_gh):
    # Arrange
    args = argparse.Namespace(
        version="2.0.0", issue=None, dry_run=False, remote="my-remote"
    )
    issue_num = mock_gh.create_issue(
        title="Release 2.0.0",
        body="- [ ] Tag Final",
        labels=["type: release"],
    )
    mock_git.get_remote_tags.return_value = ["2.0.0-rc1"]
    mock_git.tag_exists.return_value = False
    mock_git.get_commit_sha.return_value = "abcdef123456"

    # Act
    result = Promote(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    mock_git.fetch.assert_has_calls(
        [
            call("my-remote", tags=True, force=True),
            call("my-remote", refspec="release/2.0"),
        ]
    )
    mock_git.get_commit_sha.assert_has_calls(
        [call("2.0.0-rc1"), call("my-remote/release/2.0")]
    )
    mock_git.checkout.assert_not_called()
    mock_git.tag.assert_called_once_with("2.0.0", "abcdef123456")
    mock_git.push.assert_called_once_with("my-remote", "2.0.0")

    expected_updated_body = "- [x] Tag Final | status=done tag=2.0.0 commit= abcdef12"
    assert mock_gh.get_issue_body(issue_num) == expected_updated_body


def test_promote_patch_success(mock_git, mock_gh):
    # Arrange
    issue_num = mock_gh.create_issue(
        title="Release 2.0.1",
        body="- [ ] Tag Final",
        labels=["type: release"],
    )
    args = argparse.Namespace(
        version="2.0.1", issue=issue_num, dry_run=False, remote="my-remote"
    )
    mock_git.tag_exists.return_value = False
    mock_git.get_commit_sha.return_value = "12345678"

    # Act
    result = Promote(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    mock_git.fetch.assert_has_calls(
        [
            call("my-remote", tags=True, force=True),
            call("my-remote", refspec="release/2.0"),
        ]
    )
    mock_git.get_current_branch.assert_not_called()
    mock_git.get_tags.assert_not_called()
    mock_git.get_remote_tags.assert_not_called()

    mock_git.checkout.assert_not_called()
    mock_git.get_commit_sha.assert_called_once_with("my-remote/release/2.0")
    mock_git.tag.assert_called_once_with("2.0.1", "12345678")
    mock_git.push.assert_called_once_with("my-remote", "2.0.1")

    expected_updated_body = "- [x] Tag Final | status=done tag=2.0.1 commit= 12345678"
    assert mock_gh.get_issue_body(issue_num) == expected_updated_body


@patch("builtins.print")
def test_promote_rc_dry_run_success(mock_print, mock_git, mock_gh):
    # Arrange
    issue_num = mock_gh.create_issue(
        title="Release 2.0.0",
        body="- [ ] Tag Final",
        labels=["type: release"],
    )
    args = argparse.Namespace(
        version="2.0.0", issue=issue_num, dry_run=True, remote="my-remote"
    )
    mock_git.get_remote_tags.return_value = ["2.0.0-rc0", "2.0.0-rc1"]
    mock_git.get_commit_sha.return_value = "abcdef123456"
    mock_git.tag_exists.return_value = False

    # Act
    result = Promote(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    mock_git.fetch.assert_has_calls(
        [
            call("my-remote", tags=True, force=True),
            call("my-remote", refspec="release/2.0"),
        ]
    )
    mock_git.get_commit_sha.assert_has_calls(
        [call("2.0.0-rc1"), call("my-remote/release/2.0")]
    )
    mock_git.tag_exists.assert_called_once_with("2.0.0")

    # Core dry-run assertions: NO modifications
    mock_git.tag.assert_not_called()
    mock_git.push.assert_not_called()

    mock_print.assert_has_calls(
        [
            call(f"Verifying tracking issue #{issue_num} format..."),
            call("Fetching remote branch my-remote/release/2.0..."),
            call(
                "[DRY RUN] Pre-conditions passed successfully for promoting"
                " 2.0.0-rc1 to 2.0.0."
            ),
            call("[DRY RUN] Would tag commit abcdef12 as 2.0.0"),
            call("[DRY RUN] Would push tag 2.0.0 to my-remote"),
            call(f"[DRY RUN] Would update tracking issue #{issue_num} checklist"),
            call(f"[DRY RUN] Would post comment to tracking issue #{issue_num}"),
        ]
    )


def test_promote_rc_tag_already_exists(mock_git, mock_gh):
    # Arrange
    args = argparse.Namespace(
        version="2.0.0", issue=123, dry_run=False, remote="my-remote"
    )
    mock_git.get_remote_tags.return_value = ["2.0.0-rc1"]
    mock_git.tag_exists.return_value = True

    # Act
    result = Promote(args, mock_git, mock_gh).run()

    # Assert
    assert result == 1
    mock_git.checkout.assert_not_called()
    mock_git.tag.assert_not_called()
    mock_git.push.assert_not_called()


def test_promote_rc_issue_not_found(mock_git, mock_gh):
    # Arrange
    args = argparse.Namespace(
        version="2.0.0", issue=None, dry_run=False, remote="my-remote"
    )
    mock_git.get_remote_tags.return_value = ["2.0.0-rc1"]
    mock_git.tag_exists.return_value = False

    # Act
    result = Promote(args, mock_git, mock_gh).run()

    # Assert
    assert result == 1
    mock_git.checkout.assert_not_called()
    mock_git.tag.assert_not_called()
    mock_git.push.assert_not_called()


def test_promote_rc_issue_malformed(mock_git, mock_gh):
    # Arrange
    issue_num = mock_gh.create_issue(
        title="Release 2.0.0",
        body="malformed body",
        labels=["type: release"],
    )
    args = argparse.Namespace(
        version="2.0.0", issue=issue_num, dry_run=False, remote="my-remote"
    )
    mock_git.get_remote_tags.return_value = ["2.0.0-rc1"]
    mock_git.tag_exists.return_value = False
    mock_git.get_commit_sha.return_value = "abcdef123456"

    # Act
    result = Promote(args, mock_git, mock_gh).run()

    # Assert
    assert result == 1
    mock_git.checkout.assert_not_called()
    mock_git.tag.assert_not_called()
    mock_git.push.assert_not_called()


def test_promote_rc_no_rc_found(mock_git, mock_gh):
    # Arrange
    args = argparse.Namespace(
        version="2.0.0", issue=123, dry_run=False, remote="my-remote"
    )
    mock_git.get_remote_tags.return_value = []

    # Act
    result = Promote(args, mock_git, mock_gh).run()

    # Assert
    assert result == 1
    mock_git.checkout.assert_not_called()
    mock_git.tag.assert_not_called()

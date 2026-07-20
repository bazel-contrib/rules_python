import argparse
import os
import pathlib
import tempfile
from unittest.mock import call

from tools.private.release.create_rc import CreateRc

pytest_plugins = ["tests.tools.private.release.release_test_helper"]


def test_create_rc_success_first_rc(mocker, mock_git, mock_gh):
    # Arrange
    args = argparse.Namespace(
        issue=123, remote="my-remote", triggering_comment=None, dry_run=False
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
- [ ] Tag RC0 | status=pending
""",
        "labels": ["type: release"],
    }
    mock_git.get_remote_tags.return_value = []
    mock_git.get_commit_sha.return_value = "1234567890"

    # Act
    with tempfile.TemporaryDirectory() as tmpdir:
        github_output_file = pathlib.Path(tmpdir) / "github_output"
        mocker.patch.dict(os.environ, {"GITHUB_OUTPUT": str(github_output_file)})
        result = CreateRc(args, mock_git, mock_gh).run()

        # Assert
        assert result == 0
        assert github_output_file.exists()
        assert github_output_file.read_text() == "tag_name=2.0.0-rc0\n"

    mock_git.fetch.assert_has_calls(
        [call("my-remote"), call("my-remote", tags=True, force=True)]
    )
    mock_git.checkout.assert_not_called()
    mock_git.tag.assert_called_once_with("2.0.0-rc0", "my-remote/release/2.0")
    mock_git.push.assert_called_once_with("my-remote", "2.0.0-rc0")
    mock_git.get_commit_sha.assert_called_once_with("my-remote/release/2.0")

    updated_body = mock_gh.get_issue_body(123)
    assert "tag=2.0.0-rc0" in updated_body
    assert "commit= 12345678" in updated_body

    assert 123 in mock_gh.issue_comments
    comment_text = mock_gh.issue_comments[123][0]
    assert "**New Release Candidate Tagged!** 🐍🌿" in comment_text
    assert (
        "tagged on branch [`release/2.0`](https://github.com/bazel-contrib/rules_python/tree/release/2.0)"
        in comment_text
    )
    assert (
        "- [Github Release 2.0.0-rc0](https://github.com/bazel-contrib/rules_python/releases/tag/2.0.0-rc0)"
        in comment_text
    )
    assert (
        "- [BCR Entry 2.0.0-rc0](https://registry.bazel.build/modules/rules_python/2.0.0-rc0)"
        in comment_text
    )
    assert (
        "- [BCR PRs](https://github.com/bazelbuild/bazel-central-registry/pulls?q=is%3Apr+rules_python+2.0.0-rc0)"
        in comment_text
    )
    assert (
        "- [Release workflow status](https://github.com/bazel-contrib/rules_python/actions/workflows/release_create_rc.yaml)"
        in comment_text
    )


def test_create_rc_success_with_run_id(mocker, mock_git, mock_gh):
    # Arrange
    args = argparse.Namespace(
        issue=123, remote="my-remote", triggering_comment=None, dry_run=False
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
- [ ] Tag RC0 | status=pending
""",
        "labels": ["type: release"],
    }
    mock_git.get_remote_tags.return_value = []
    mock_git.get_commit_sha.return_value = "1234567890"

    # Act
    mocker.patch.dict(os.environ, {"GITHUB_RUN_ID": "987654321"})
    result = CreateRc(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    assert 123 in mock_gh.issue_comments
    comment_text = mock_gh.issue_comments[123][0]
    assert (
        "- [Release workflow status](https://github.com/bazel-contrib/rules_python/actions/runs/987654321)"
        in comment_text
    )
    assert (
        "tagged on branch [`release/2.0`](https://github.com/bazel-contrib/rules_python/tree/release/2.0)"
        in comment_text
    )


def test_create_rc_success_next_rc(mock_git, mock_gh):
    # Arrange
    args = argparse.Namespace(
        issue=123, remote="my-remote", triggering_comment=None, dry_run=False
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
- [x] Tag RC0 | status=done tag=2.0.0-rc0 commit=abcdef12
- [ ] Tag RC1 | status=pending
""",
        "labels": ["type: release"],
    }
    mock_git.get_remote_tags.return_value = ["2.0.0-rc0"]
    mock_git.get_commit_sha.return_value = "1234567890"

    # Act
    result = CreateRc(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    mock_git.fetch.assert_has_calls(
        [call("my-remote"), call("my-remote", tags=True, force=True)]
    )
    mock_git.checkout.assert_not_called()
    mock_git.tag.assert_called_once_with("2.0.0-rc1", "my-remote/release/2.0")
    mock_git.push.assert_called_once_with("my-remote", "2.0.0-rc1")
    mock_git.get_commit_sha.assert_called_once_with("my-remote/release/2.0")

    updated_body = mock_gh.get_issue_body(123)
    assert "tag=2.0.0-rc1" in updated_body

    assert 123 in mock_gh.issue_comments
    comment_text = mock_gh.issue_comments[123][0]
    assert "**New Release Candidate Tagged!** 🐍🌿" in comment_text


def test_create_rc_gating_on_backports(mock_git, mock_gh):
    # Arrange
    args = argparse.Namespace(
        issue=123, remote="my-remote", triggering_comment=None, dry_run=False
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
- [ ] Tag RC0 | status=pending

## Backports
- [ ] #124 | status=pending
""",
        "labels": ["type: release"],
    }
    # Act
    result = CreateRc(args, mock_git, mock_gh).run()

    # Assert
    assert result == 1
    mock_git.tag.assert_not_called()
    mock_git.push.assert_not_called()


def test_create_rc_not_blocked_by_ignored_backports(mock_git, mock_gh):
    # Arrange
    args = argparse.Namespace(
        issue=123, remote="my-remote", triggering_comment=None, dry_run=False
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
- [ ] Tag RC0 | status=pending

## Backports
- [ ] #124 | status=ignore
""",
        "labels": ["type: release"],
    }
    mock_git.get_remote_tags.return_value = []
    mock_git.get_commit_sha.return_value = "1234567890"

    # Act
    result = CreateRc(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    mock_git.tag.assert_called_once_with("2.0.0-rc0", "my-remote/release/2.0")
    mock_git.push.assert_called_once_with("my-remote", "2.0.0-rc0")


def test_create_rc_with_finished_backports(mock_git, mock_gh):
    # Arrange
    args = argparse.Namespace(
        issue=123, remote="my-remote", triggering_comment=None, dry_run=False
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
- [ ] Tag RC0 | status=pending

## Backports
- [x] #124 | status=done rc=rc0 commit=abcdef12
""",
        "labels": ["type: release"],
    }
    mock_git.get_remote_tags.return_value = []
    mock_git.get_commit_sha.return_value = "1234567890"

    # Act
    result = CreateRc(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    mock_git.tag.assert_called_once_with("2.0.0-rc0", "my-remote/release/2.0")
    mock_git.push.assert_called_once_with("my-remote", "2.0.0-rc0")


def test_create_rc_auto_add_task(mock_git, mock_gh):
    # Arrange
    args = argparse.Namespace(
        issue=123, remote="my-remote", triggering_comment=None, dry_run=False
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
- [x] Tag RC0 | status=done tag=2.0.0-rc0 commit=abcdef12
- [ ] Tag Final
""",
        "labels": ["type: release"],
    }
    mock_git.get_remote_tags.return_value = ["2.0.0-rc0"]
    mock_git.get_commit_sha.return_value = "1234567890"

    # Act
    result = CreateRc(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    mock_git.tag.assert_called_once_with("2.0.0-rc1", "my-remote/release/2.0")
    mock_git.push.assert_called_once_with("my-remote", "2.0.0-rc1")

    updated_body = mock_gh.get_issue_body(123)
    assert "- [x] Tag RC1 | status=done tag=2.0.0-rc1 commit= 12345678" in updated_body


def test_create_rc_calls_process_backports(mocker, mock_git, mock_gh):
    # Arrange
    mock_pb_class = mocker.patch("tools.private.release.create_rc.ProcessBackports")
    mock_pb = mock_pb_class.return_value
    mock_pb.run.return_value = 0

    args = argparse.Namespace(
        issue=123, remote="my-remote", triggering_comment=None, dry_run=False
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
- [ ] Tag RC0 | status=pending
""",
        "labels": ["type: release"],
    }
    mock_git.get_remote_tags.return_value = []
    mock_git.get_commit_sha.return_value = "1234567890"

    # Act
    result = CreateRc(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    mock_pb_class.assert_called_once()
    called_args = mock_pb_class.call_args[0][0]
    assert called_args.issue == 123
    assert called_args.remote == "my-remote"
    assert not called_args.dry_run
    assert called_args.add is None
    assert called_args.triggering_comment is None
    mock_pb.run.assert_called_once()


def test_create_rc_aborts_on_process_backports_failure(mocker, mock_git, mock_gh):
    # Arrange
    mock_pb_class = mocker.patch("tools.private.release.create_rc.ProcessBackports")
    mock_pb = mock_pb_class.return_value
    mock_pb.run.return_value = 1

    args = argparse.Namespace(
        issue=123, remote="my-remote", triggering_comment=None, dry_run=False
    )

    # Act
    result = CreateRc(args, mock_git, mock_gh).run()

    # Assert
    assert result == 1
    mock_pb_class.assert_called_once()
    mock_pb.run.assert_called_once()
    mock_git.tag.assert_not_called()


def test_create_rc_failure_reacts_to_comment(mocker, mock_git, mock_gh):
    # Arrange
    mock_pb_class = mocker.patch("tools.private.release.create_rc.ProcessBackports")
    mock_pb = mock_pb_class.return_value
    mock_pb.run.return_value = 1  # Simulate failure

    args = argparse.Namespace(
        issue=123, remote="my-remote", triggering_comment=456, dry_run=False
    )

    # Act
    result = CreateRc(args, mock_git, mock_gh).run()

    # Assert
    assert result == 1
    assert mock_gh.reactions.get(456) == ["-1"]


def test_create_rc_failure_no_comment_no_reaction(mocker, mock_git, mock_gh):
    # Arrange
    mock_pb_class = mocker.patch("tools.private.release.create_rc.ProcessBackports")
    mock_pb = mock_pb_class.return_value
    mock_pb.run.return_value = 1  # Simulate failure

    args = argparse.Namespace(
        issue=123, remote="my-remote", triggering_comment=None, dry_run=False
    )

    # Act
    result = CreateRc(args, mock_git, mock_gh).run()

    # Assert
    assert result == 1
    assert 456 not in mock_gh.reactions


def test_create_rc_success_with_comment_no_reaction(mocker, mock_git, mock_gh):
    # Arrange
    mock_pb_class = mocker.patch("tools.private.release.create_rc.ProcessBackports")
    mock_pb = mock_pb_class.return_value
    mock_pb.run.return_value = 0

    args = argparse.Namespace(
        issue=123, remote="my-remote", triggering_comment=456, dry_run=False
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
- [ ] Tag RC0 | status=pending
""",
        "labels": ["type: release"],
    }
    mock_git.get_remote_tags.return_value = []
    mock_git.get_commit_sha.return_value = "1234567890"

    # Act
    result = CreateRc(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    assert 456 not in mock_gh.reactions


def test_create_rc_precondition_failure_reacts_to_comment(mocker, mock_git, mock_gh):
    # Arrange
    mock_pb_class = mocker.patch("tools.private.release.create_rc.ProcessBackports")
    mock_pb = mock_pb_class.return_value
    mock_pb.run.return_value = 0  # Backports succeed

    args = argparse.Namespace(
        issue=123, remote="my-remote", triggering_comment=456, dry_run=False
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [ ] Prepare Release | status=pending
- [ ] Create Release branch | status=pending
- [ ] Tag RC0 | status=pending
""",
        "labels": ["type: release"],
    }

    # Act
    result = CreateRc(args, mock_git, mock_gh).run()

    # Assert
    assert result == 1
    assert mock_gh.reactions.get(456) == ["-1"]

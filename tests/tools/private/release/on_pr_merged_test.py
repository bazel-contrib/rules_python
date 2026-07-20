import argparse
from unittest.mock import MagicMock

from tools.private.release.on_pr_merged import OnPrMerged

pytest_plugins = ["tests.tools.private.release.release_test_helper"]


def test_on_pr_merged_no_comment(mocker, mock_git, mock_gh):
    args = argparse.Namespace(pr=124, remote="origin", dry_run=True)
    mock_gh.pr_comments = {
        124: [
            {"body": "Some comment"},
            {"body": "Another comment /backport_wrong"},
        ]
    }

    mock_pb = mocker.patch("tools.private.release.on_pr_merged.ProcessBackports")
    result = OnPrMerged(args, mock_git, mock_gh).run()

    assert result == 1
    mock_pb.assert_not_called()


def test_on_pr_merged_has_comment_no_active_release(mocker, mock_git, mock_gh):
    args = argparse.Namespace(pr=124, remote="origin", dry_run=True)
    mock_gh.pr_comments = {124: [{"body": "/backport"}]}

    mock_pb = mocker.patch("tools.private.release.on_pr_merged.ProcessBackports")
    result = OnPrMerged(args, mock_git, mock_gh).run()

    assert result == 1
    mock_pb.assert_not_called()


def test_on_pr_merged_has_comment_not_in_backports(mocker, mock_git, mock_gh):
    args = argparse.Namespace(pr=124, remote="origin", dry_run=True)
    mock_gh.pr_comments = {124: [{"body": "  /backport  "}]}
    mock_gh.create_issue(
        title="Release 2.1.0",
        body="""
## Checklist
- [ ] Prepare Release

## Backports
- [ ] #125 | status=pending
""",
        labels=["type: release"],
    )

    mock_pb = mocker.patch("tools.private.release.on_pr_merged.ProcessBackports")
    result = OnPrMerged(args, mock_git, mock_gh).run()

    assert result == 1
    mock_pb.assert_not_called()


def test_on_pr_merged_success(mocker, mock_git, mock_gh):
    args = argparse.Namespace(pr=124, remote="origin", dry_run=True)
    mock_gh.pr_comments = {124: [{"body": "/backport"}]}
    issue_num = mock_gh.create_issue(
        title="Release 2.1.0",
        body="""
## Checklist
- [ ] Prepare Release

## Backports
- [ ] #124 | status=pending
""",
        labels=["type: release"],
    )

    mock_pb_class = mocker.patch("tools.private.release.on_pr_merged.ProcessBackports")
    mock_pb_instance = MagicMock()
    mock_pb_instance.run.return_value = 0
    mock_pb_class.return_value = mock_pb_instance

    result = OnPrMerged(args, mock_git, mock_gh).run()

    assert result == 0

    # Verify ProcessBackports was instantiated with correct args
    mock_pb_class.assert_called_once()
    called_args = mock_pb_class.call_args[0][0]
    assert called_args.issue == issue_num
    assert called_args.remote == "origin"
    assert called_args.dry_run is True
    assert called_args.add is None
    assert called_args.triggering_comment is None

    # Verify ProcessBackports.run() was called
    mock_pb_instance.run.assert_called_once()

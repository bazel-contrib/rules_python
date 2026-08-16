import pytest

from tools.private.release import release as releaser


def test_valid_version():
    # These should not raise an exception
    releaser.create_parser().parse_args(["prepare", "0.28.0"])
    releaser.create_parser().parse_args(["promote", "1.0.0", "--remote", "origin"])
    releaser.create_parser().parse_args(
        ["create-release-issue", "--version", "1.2.3rc4"]
    )


def test_invalid_version():
    with pytest.raises(SystemExit):
        releaser.create_parser().parse_args(["prepare", "0.28"])
    with pytest.raises(SystemExit):
        releaser.create_parser().parse_args(["prepare", "a.b.c"])


def test_main_runs_command(mocker):
    mocker.patch("sys.argv", ["release", "prepare", "0.28.0"])
    mock_cmd = mocker.patch(
        "tools.private.release.prepare.Prepare.run_from_args", return_value=0
    )
    with pytest.raises(SystemExit) as exc_info:
        releaser.main()
    assert exc_info.value.code == 0
    mock_cmd.assert_called_once()

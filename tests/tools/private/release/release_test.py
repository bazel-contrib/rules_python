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

import pytest

from tools.private.release import utils

pytest_plugins = ["tests.tools.private.release.release_test_helper"]


def test_get_latest_version_success(mocker):
    mocker.patch(
        "tools.private.release.git.Git.get_tags",
        return_value=["0.1.0", "1.0.0", "0.2.0"],
    )
    assert utils.get_latest_version() == "1.0.0"


def test_get_latest_version_rc_is_latest(mocker):
    mocker.patch(
        "tools.private.release.git.Git.get_tags",
        return_value=["0.1.0", "1.0.0", "1.1.0rc0"],
    )
    with pytest.raises(
        ValueError, match="The latest version is a pre-release version: 1.1.0rc0"
    ):
        utils.get_latest_version()


def test_get_latest_version_no_tags(mocker):
    mocker.patch("tools.private.release.git.Git.get_tags", return_value=[])
    with pytest.raises(
        RuntimeError, match="No git tags found matching X.Y.Z or X.Y.ZrcN format."
    ):
        utils.get_latest_version()


def test_get_latest_version_no_matching_tags(mocker):
    mocker.patch(
        "tools.private.release.git.Git.get_tags", return_value=["v1.0", "latest"]
    )
    with pytest.raises(
        RuntimeError, match="No git tags found matching X.Y.Z or X.Y.ZrcN format."
    ):
        utils.get_latest_version()


def test_get_latest_version_only_rc_tags(mocker):
    mocker.patch(
        "tools.private.release.git.Git.get_tags", return_value=["1.0.0rc0", "1.1.0rc0"]
    )
    with pytest.raises(
        ValueError, match="The latest version is a pre-release version: 1.1.0rc0"
    ):
        utils.get_latest_version()


def test_get_latest_rc_tag_no_tags(mocker):
    mocker.patch("tools.private.release.git.Git.get_tags", return_value=[])
    assert utils.get_latest_rc_tag("2.0.0") is None


def test_get_latest_rc_tag_no_matching_tags(mocker):
    mocker.patch(
        "tools.private.release.git.Git.get_tags",
        return_value=[
            "1.0.0",
            "2.0.0",
            "v2.0.0-rc0",
            "2.1.0-rc0",
        ],
    )
    assert utils.get_latest_rc_tag("2.0.0") is None


def test_get_latest_rc_tag_success(mocker):
    mocker.patch(
        "tools.private.release.git.Git.get_tags",
        return_value=[
            "2.0.0-rc0",
            "2.0.0-rc2",
            "2.0.0-rc1",
            "2.1.0-rc0",
        ],
    )
    assert utils.get_latest_rc_tag("2.0.0") == "2.0.0-rc2"


def test_get_latest_rc_tag_ignores_v_prefix(mocker):
    mocker.patch(
        "tools.private.release.git.Git.get_tags",
        return_value=["v2.0.0-rc0", "2.0.0-rc1"],
    )
    assert utils.get_latest_rc_tag("2.0.0") == "2.0.0-rc1"


def test_get_latest_rc_tag_remote_success(mocker):
    mock_get_remote_tags = mocker.patch(
        "tools.private.release.git.Git.get_remote_tags",
        return_value=[
            "2.0.0-rc0",
            "2.0.0-rc2",
            "2.0.0-rc1",
            "2.1.0-rc0",
        ],
    )
    assert utils.get_latest_rc_tag("2.0.0", remote="origin") == "2.0.0-rc2"
    mock_get_remote_tags.assert_called_once_with("origin")


def test_determine_next_version_no_markers(mocker, release_tool_env):
    mocker.patch(
        "tools.private.release.git.Git.get_current_branch", return_value="main"
    )
    mocker.patch("tools.private.release.utils.get_latest_version", return_value="1.2.3")
    (release_tool_env.git_root / "mock_file.bzl").write_text("no markers here")

    next_version = utils.determine_next_version()

    assert next_version == "1.2.4"


def test_determine_next_version_only_patch(mocker, release_tool_env):
    mocker.patch(
        "tools.private.release.git.Git.get_current_branch", return_value="main"
    )
    mocker.patch("tools.private.release.utils.get_latest_version", return_value="1.2.3")
    (release_tool_env.git_root / "mock_file.bzl").write_text(
        ":::{versionchanged} VERSION_NEXT_PATCH"
    )

    next_version = utils.determine_next_version()

    assert next_version == "1.2.4"


def test_determine_next_version_only_feature(mocker, release_tool_env):
    mocker.patch(
        "tools.private.release.git.Git.get_current_branch", return_value="main"
    )
    mocker.patch("tools.private.release.utils.get_latest_version", return_value="1.2.3")
    (release_tool_env.git_root / "mock_file.bzl").write_text(
        ":::{versionadded} VERSION_NEXT_FEATURE"
    )

    next_version = utils.determine_next_version()

    assert next_version == "1.3.0"


def test_determine_next_version_both_markers(mocker, release_tool_env):
    mocker.patch(
        "tools.private.release.git.Git.get_current_branch", return_value="main"
    )
    mocker.patch("tools.private.release.utils.get_latest_version", return_value="1.2.3")
    (release_tool_env.git_root / "mock_file_patch.bzl").write_text(
        ":::{versionchanged} VERSION_NEXT_PATCH"
    )
    (release_tool_env.git_root / "mock_file_feature.bzl").write_text(
        ":::{versionadded} VERSION_NEXT_FEATURE"
    )

    next_version = utils.determine_next_version()

    assert next_version == "1.3.0"


def test_determine_next_version_on_release_branch_with_existing_tags(mocker):
    mocker.patch(
        "tools.private.release.git.Git.get_current_branch", return_value="release/0.37"
    )
    mocker.patch(
        "tools.private.release.git.Git.get_tags",
        return_value=["0.37.0", "0.37.1", "0.36.0"],
    )

    next_version = utils.determine_next_version()

    assert next_version == "0.37.2"


def test_determine_next_version_on_release_branch_no_tags(mocker):
    mocker.patch(
        "tools.private.release.git.Git.get_current_branch", return_value="release/0.38"
    )
    mocker.patch(
        "tools.private.release.git.Git.get_tags", return_value=["0.37.0"]
    )  # No 0.38.x tags

    next_version = utils.determine_next_version()

    assert next_version == "0.38.0"


def test_determine_next_version_on_release_branch_with_active_rc(mocker):
    mocker.patch(
        "tools.private.release.git.Git.get_current_branch", return_value="release/0.37"
    )
    # 0.37.0-rc0 and rc1 exist, but no stable 0.37.0 yet
    mocker.patch(
        "tools.private.release.git.Git.get_tags",
        return_value=["0.37.0-rc0", "0.37.0-rc1", "0.36.0"],
    )

    next_version = utils.determine_next_version()

    # Should target 0.37.0, not 0.37.1
    assert next_version == "0.37.0"


def test_determine_next_version_on_release_branch_with_stable_and_active_patch_rc(
    mocker,
):
    mocker.patch(
        "tools.private.release.git.Git.get_current_branch", return_value="release/0.37"
    )
    # 0.37.0 stable exists, and 0.37.1-rc0 exists (but no stable 0.37.1 yet)
    mocker.patch(
        "tools.private.release.git.Git.get_tags",
        return_value=["0.37.0", "0.37.1-rc0", "0.36.0"],
    )

    next_version = utils.determine_next_version()

    # Should target 0.37.1, not 0.37.2
    assert next_version == "0.37.1"


def test_determine_next_version_on_main_branch_fallback(mocker, release_tool_env):
    mocker.patch(
        "tools.private.release.git.Git.get_current_branch", return_value="main"
    )
    mocker.patch("tools.private.release.utils.get_latest_version", return_value="1.2.3")
    (release_tool_env.git_root / "mock_file.bzl").write_text("no markers here")

    next_version = utils.determine_next_version()

    assert next_version == "1.2.4"


def test_replace_version_next(release_tool_env):
    # Arrange
    mock_file_content = """
:::{versionadded} VERSION_NEXT_FEATURE
blabla
:::

:::{versionchanged} VERSION_NEXT_PATCH
blabla
:::
"""
    (release_tool_env.git_root / "mock_file.bzl").write_text(mock_file_content)

    utils.replace_version_next("0.28.0")

    new_content = (release_tool_env.git_root / "mock_file.bzl").read_text()

    assert ":::{versionadded} 0.28.0" in new_content
    assert "VERSION_NEXT_FEATURE" not in new_content
    assert "VERSION_NEXT_PATCH" not in new_content


def test_replace_version_next_excludes_bazel_dirs(release_tool_env):
    # Arrange
    mock_file_content = """
:::{versionadded} VERSION_NEXT_FEATURE
blabla
:::
"""
    bazel_dir = release_tool_env.git_root / "bazel-rules_python"
    bazel_dir.mkdir()
    (bazel_dir / "mock_file.bzl").write_text(mock_file_content)

    tools_dir = release_tool_env.git_root / "tools" / "private" / "release"
    tools_dir.mkdir(parents=True)
    (tools_dir / "mock_file.bzl").write_text(mock_file_content)

    tests_dir = release_tool_env.git_root / "tests" / "tools" / "private" / "release"
    tests_dir.mkdir(parents=True)
    (tests_dir / "mock_file.bzl").write_text(mock_file_content)

    version = "0.28.0"

    # Act
    utils.replace_version_next(version)

    # Assert
    new_content = (bazel_dir / "mock_file.bzl").read_text()
    assert "VERSION_NEXT_FEATURE" in new_content

    new_content = (tools_dir / "mock_file.bzl").read_text()
    assert "VERSION_NEXT_FEATURE" in new_content

    new_content = (tests_dir / "mock_file.bzl").read_text()
    assert "VERSION_NEXT_FEATURE" in new_content

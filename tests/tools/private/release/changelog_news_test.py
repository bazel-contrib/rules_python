import pathlib

import pytest

from tools.private.release import changelog_news


def test_update_changelog_with_news(tmp_path):
    # Arrange
    changelog = """# Changelog

{#unreleased}
## Unreleased

[unreleased]: https://github.com/bazel-contrib/rules_python/releases/tag/unreleased

Unreleased changes are tracked as individual files in the [news/](./news)
directory, or view the [latest generated
changelog](https://rules-python.readthedocs.io/en/latest/changelog.html).

{#v2-0-2}
## [2.0.2] - 2026-05-14

[2.0.2]: https://github.com/bazel-contrib/rules_python/releases/tag/2.0.2

{#v2-0-2-added}
### Added
* (toolchains) Some older change.
"""
    changelog_path = tmp_path / "CHANGELOG.md"
    changelog_path.write_text(changelog)

    news_dir = tmp_path / "news"
    news_dir.mkdir()

    # Create news files
    (news_dir / "123.fixed.md").write_text("Fixed a bug in the compiler")
    # Test that it handles prefixing "* " if not present
    (news_dir / "456.added.md").write_text("* Added a new feature for Python 3.13")
    # Empty file should be ignored
    (news_dir / "789.changed.md").write_text("")
    # Invalid name should be ignored
    (news_dir / "invalid_name.md").write_text("Should be ignored")

    # Act
    changelog_news.update_changelog(
        "3.0.0",
        "2026-06-16",
        changelog_path=changelog_path,
        news_dir=news_dir,
    )

    # Assert
    # 1. News files matching the pattern should be deleted (even empty ones)
    assert not (news_dir / "123.fixed.md").exists()
    assert not (news_dir / "456.added.md").exists()
    assert not (news_dir / "789.changed.md").exists()
    # Invalid name does not match pattern -> NOT deleted
    assert (news_dir / "invalid_name.md").exists()

    new_content = changelog_path.read_text()

    # 2. A fresh active Unreleased section should be present
    assert "{#unreleased}" in new_content
    assert "## Unreleased" in new_content
    assert (
        "Unreleased changes are tracked as individual files in the [news/](./news)\n"
        "directory, or view the [latest generated\n"
        "changelog](https://rules-python.readthedocs.io/en/latest/changelog.html)."
        in new_content
    )

    # 3. The new release section should be present
    assert "{#v3-0-0}" in new_content
    assert "## [3.0.0] - 2026-06-16" in new_content
    assert (
        "[3.0.0]: https://github.com/bazel-contrib/rules_python/releases/tag/3.0.0"
        in new_content
    )

    # 4. Correct categories and content
    assert "{#v3-0-0-fixed}\n### Fixed\n* Fixed a bug in the compiler" in new_content
    assert (
        "{#v3-0-0-added}\n### Added\n* Added a new feature for Python 3.13"
        in new_content
    )

    # 5. Omitted categories should NOT be present in the new release
    assert "{#v3-0-0-removed}" not in new_content
    assert "{#v3-0-0-changed}" not in new_content

    # 6. Old release should still be there
    assert "{#v2-0-2}" in new_content
    assert "## [2.0.2] - 2026-05-14" in new_content


def test_update_changelog_sorting(tmp_path):
    # Arrange
    changelog = """# Changelog

{#unreleased}
## Unreleased

[unreleased]: https://github.com/bazel-contrib/rules_python/releases/tag/unreleased

Unreleased changes are tracked as individual files in the [news/](./news)
directory, or view the [latest generated
changelog](https://rules-python.readthedocs.io/en/latest/changelog.html).

{#v2-0-2}
## [2.0.2] - 2026-05-14

[2.0.2]: https://github.com/bazel-contrib/rules_python/releases/tag/2.0.2

{#v2-0-2-added}
### Added
* (toolchains) Some older change.
"""
    changelog_path = tmp_path / "CHANGELOG.md"
    changelog_path.write_text(changelog)

    news_dir = tmp_path / "news"
    news_dir.mkdir()

    # Create news files with different sub-categories and some without
    (news_dir / "1.fixed.md").write_text("* (zebra) Zebra fix")
    (news_dir / "2.fixed.md").write_text("* (apple) Apple fix")
    (news_dir / "3.fixed.md").write_text("No subcategory B")
    (news_dir / "4.fixed.md").write_text("* (apple) Another apple fix")
    (news_dir / "5.fixed.md").write_text("No subcategory A")

    # Act
    changelog_news.update_changelog(
        "3.0.0",
        "2026-06-16",
        changelog_path=changelog_path,
        news_dir=news_dir,
    )

    # Assert
    new_content = changelog_path.read_text()

    expected_fixed_section = (
        "### Fixed\n"
        "* No subcategory A\n"
        "* No subcategory B\n"
        "* (apple) Another apple fix\n"
        "* (apple) Apple fix\n"
        "* (zebra) Zebra fix\n"
    )

    assert expected_fixed_section in new_content


pytest_plugins = ["tests.tools.private.release.release_test_helper"]


def test_update_changelog_read_failure(mocker, tmp_path):
    # Arrange
    original_read_text = pathlib.Path.read_text

    mock_read_text = mocker.patch.object(pathlib.Path, "read_text", autospec=True)

    def side_effect(path_self, *args, **kwargs):
        if "bad_file.fixed.md" in str(path_self):
            raise IOError("Simulated read error")
        return original_read_text(path_self, *args, **kwargs)

    mock_read_text.side_effect = side_effect

    changelog = """# Changelog

{#unreleased}
## Unreleased

[unreleased]: https://github.com/bazel-contrib/rules_python/releases/tag/unreleased

Unreleased changes are tracked as individual files in the [news/](./news)
directory, or view the [latest generated
changelog](https://rules-python.readthedocs.io/en/latest/changelog.html).

{#v2-0-2}
## [2.0.2] - 2026-05-14

[2.0.2]: https://github.com/bazel-contrib/rules_python/releases/tag/2.0.2

{#v2-0-2-added}
### Added
* (toolchains) Some older change.
"""
    changelog_path = tmp_path / "CHANGELOG.md"
    changelog_path.write_text(changelog)

    news_dir = tmp_path / "news"
    news_dir.mkdir()

    # Create the bad file (must exist so it is found by iterdir)
    bad_file = news_dir / "bad_file.fixed.md"
    bad_file.write_text("some content that won't be read")

    # Create a good file too
    good_file = news_dir / "good_file.fixed.md"
    good_file.write_text("* (sub) Good fix")

    # Act & Assert
    with pytest.raises(IOError):
        changelog_news.update_changelog(
            "3.0.0",
            "2026-06-16",
            changelog_path=changelog_path,
            news_dir=news_dir,
        )

    # Both files should still exist (no deletion on failure!)
    assert bad_file.exists()
    assert good_file.exists()

    # Changelog should not be modified
    new_content = changelog_path.read_text()
    assert changelog == new_content


def test_update_changelog_merge_existing(tmp_path):
    # Arrange
    changelog = """# Changelog

{#unreleased}
## Unreleased

[unreleased]: https://github.com/bazel-contrib/rules_python/releases/tag/unreleased

Unreleased changes are tracked as individual files in the [news/](./news)
directory, or view the [latest generated
changelog](https://rules-python.readthedocs.io/en/latest/changelog.html).

{#v2-0-3}
## [2.0.3] - 2026-06-15

[2.0.3]: https://github.com/bazel-contrib/rules_python/releases/tag/2.0.3

{#v2-0-3-fixed}
### Fixed
* (pypi) Old fix
  multi-line detail
  * nested bullet item
* (pypi) Z old fix
"""
    changelog_path = tmp_path / "CHANGELOG.md"
    changelog_path.write_text(changelog)

    news_dir = tmp_path / "news"
    news_dir.mkdir()

    # Create news files to merge
    (news_dir / "1.fixed.md").write_text("(pypi) New fix")
    (news_dir / "2.added.md").write_text("(toolchains) New feature")

    # Act
    changelog_news.update_changelog(
        "2.0.3",
        "2026-06-15",
        changelog_path=changelog_path,
        news_dir=news_dir,
    )

    # Assert
    assert not (news_dir / "1.fixed.md").exists()
    assert not (news_dir / "2.added.md").exists()

    new_content = changelog_path.read_text()

    expected_fixed_section = (
        "### Fixed\n"
        "* (pypi) New fix\n"
        "* (pypi) Old fix\n"
        "  multi-line detail\n"
        "  * nested bullet item\n"
        "* (pypi) Z old fix\n"
    )
    assert expected_fixed_section in new_content

    expected_added_section = "### Added\n* (toolchains) New feature\n"
    assert expected_added_section in new_content
    assert "Unreleased changes are tracked as individual files" in new_content


def test_update_changelog_does_not_leak(tmp_path):
    # Arrange
    changelog = """# Changelog

{#unreleased}
## Unreleased

[unreleased]: https://github.com/bazel-contrib/rules_python/releases/tag/unreleased

Unreleased changes are tracked as individual files in the [news/](./news)
directory, or view the [latest generated
changelog](https://rules-python.readthedocs.io/en/latest/changelog.html).

{#v2-0-2}
## [2.0.2] - 2026-05-14

[2.0.2]: https://github.com/bazel-contrib/rules_python/releases/tag/2.0.2

This release body mentions the word unreleased and {#unreleased} anchor to test leaks.
"""
    changelog_path = tmp_path / "CHANGELOG.md"
    changelog_path.write_text(changelog)

    news_dir = tmp_path / "news"
    news_dir.mkdir()
    (news_dir / "1.fixed.md").write_text("Some fix")

    # Act
    changelog_news.update_changelog(
        "3.0.0",
        "2026-06-16",
        changelog_path=changelog_path,
        news_dir=news_dir,
    )

    # Assert
    new_content = changelog_path.read_text()
    assert (
        "This release body mentions the word unreleased and {#unreleased} anchor to test leaks."
        in new_content
    )


def test_update_changelog_empty_news(tmp_path):
    # Arrange
    changelog = """# Changelog

{#unreleased}
## Unreleased

[unreleased]: https://github.com/bazel-contrib/rules_python/releases/tag/unreleased

Unreleased changes are tracked as individual files in the [news/](./news)
directory, or view the [latest generated
changelog](https://rules-python.readthedocs.io/en/latest/changelog.html).

{#v2-0-2}
## [2.0.2] - 2026-05-14

[2.0.2]: https://github.com/bazel-contrib/rules_python/releases/tag/2.0.2

{#v2-0-2-added}
### Added
* (toolchains) Some older change.
"""
    changelog_path = tmp_path / "CHANGELOG.md"
    changelog_path.write_text(changelog)

    news_dir = tmp_path / "news"
    news_dir.mkdir()

    # Act
    changelog_news.update_changelog(
        "3.0.0",
        "2026-06-16",
        changelog_path=changelog_path,
        news_dir=news_dir,
    )

    # Assert
    new_content = changelog_path.read_text()

    assert "{#v3-0-0}" in new_content
    assert "## [3.0.0] - 2026-06-16" in new_content
    assert (
        "[3.0.0]: https://github.com/bazel-contrib/rules_python/releases/tag/3.0.0"
        in new_content
    )
    assert "No notable changes." in new_content
    assert "{#v3-0-0-fixed}" not in new_content
    assert "{#v3-0-0-added}" not in new_content


def test_update_changelog_selective_news_files(tmp_path):
    # Arrange
    changelog = """# Changelog

{#unreleased}
## Unreleased

[unreleased]: https://github.com/bazel-contrib/rules_python/releases/tag/unreleased

{#v2-0-2}
## [2.0.2] - 2026-05-14

[2.0.2]: https://github.com/bazel-contrib/rules_python/releases/tag/2.0.2
"""
    changelog_path = tmp_path / "CHANGELOG.md"
    changelog_path.write_text(changelog)

    news_dir = tmp_path / "news"
    news_dir.mkdir()

    # Create news files
    (news_dir / "123.fixed.md").write_text("Fix A")
    (news_dir / "456.fixed.md").write_text("Fix B")

    # Act: Only process 123.fixed.md
    changelog_news.update_changelog(
        "2.0.3",
        "2026-06-16",
        changelog_path=changelog_path,
        news_dir=news_dir,
        news_files=[news_dir / "123.fixed.md"],
    )

    # Assert
    assert not (news_dir / "123.fixed.md").exists()
    assert (news_dir / "456.fixed.md").exists()

    new_content = changelog_path.read_text()
    assert "Fix A" in new_content
    assert "Fix B" not in new_content


def test_update_changelog_insertion_point(tmp_path):
    # Arrange
    changelog = """# Changelog

{#unreleased}
## Unreleased

[unreleased]: https://github.com/bazel-contrib/rules_python/releases/tag/unreleased

{#v2-2-0}
## [2.2.0] - 2026-06-30

[2.2.0]: https://github.com/bazel-contrib/rules_python/releases/tag/2.2.0

{#v2-0-0}
## [2.0.0] - 2026-04-09

[2.0.0]: https://github.com/bazel-contrib/rules_python/releases/tag/2.0.0
"""
    changelog_path = tmp_path / "CHANGELOG.md"
    changelog_path.write_text(changelog)

    news_dir = tmp_path / "news"
    news_dir.mkdir()
    (news_dir / "123.fixed.md").write_text("Fix in 2.1.0")

    # Act: Insert 2.1.0
    changelog_news.update_changelog(
        "2.1.0",
        "2026-06-17",
        changelog_path=changelog_path,
        news_dir=news_dir,
    )

    # Assert
    new_content = changelog_path.read_text()

    idx_2_2_0 = new_content.index("{#v2-2-0}")
    idx_2_1_0 = new_content.index("{#v2-1-0}")
    idx_2_0_0 = new_content.index("{#v2-0-0}")

    assert idx_2_2_0 < idx_2_1_0 < idx_2_0_0
    assert "Fix in 2.1.0" in new_content


def test_update_changelog_insertion_point_too_small(tmp_path):
    # Arrange
    changelog = """# Changelog

{#unreleased}
## Unreleased

[unreleased]: https://github.com/bazel-contrib/rules_python/releases/tag/unreleased

{#v2-0-0}
## [2.0.0] - 2026-04-09

[2.0.0]: https://github.com/bazel-contrib/rules_python/releases/tag/2.0.0
"""
    changelog_path = tmp_path / "CHANGELOG.md"
    changelog_path.write_text(changelog)

    news_dir = tmp_path / "news"
    news_dir.mkdir()
    (news_dir / "123.fixed.md").write_text("Fix in 1.0.0")

    # Act & Assert
    with pytest.raises(
        ValueError, match="Could not find a version in CHANGELOG.md smaller than 1.0.0"
    ):
        changelog_news.update_changelog(
            "1.0.0",
            "2026-01-01",
            changelog_path=changelog_path,
            news_dir=news_dir,
        )

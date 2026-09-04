import argparse

from tools.private.release.process_news import ProcessNews
from tools.private.release.release import create_parser

pytest_plugins = ["tests.tools.private.release.release_test_helper"]


_CHANGELOG_TEMPLATE = """# rules_python Changelog

{#unreleased}
## Unreleased

[unreleased]: https://github.com/bazel-contrib/rules_python/releases/tag/unreleased

Unreleased changes are tracked as individual files in the [news/](./news)
directory, or view the [latest generated
changelog](https://rules-python.readthedocs.io/en/latest/changelog.html).

{#v2-3-0}
## [2.3.0] - 2026-08-07

[2.3.0]: https://github.com/bazel-contrib/rules_python/releases/tag/2.3.0

{#v2-3-0-fixed}
### Fixed
* (pypi) Fixed something.

{#v2-3-0-added}
### Added
* (cc) Added experimental feature.
"""


def test_process_news_single_file(tmp_path, monkeypatch, mock_gh):
    monkeypatch.chdir(tmp_path)
    changelog = tmp_path / "CHANGELOG.md"
    changelog.write_text(_CHANGELOG_TEMPLATE, encoding="utf-8")

    news_dir = tmp_path / "news"
    news_dir.mkdir()
    news_file = news_dir / "3997.added.md"
    news_file.write_text("(bzlmod) Added explicit_init_py tag class.", encoding="utf-8")

    args = argparse.Namespace(
        version="2.3.0",
        targets=[str(news_file)],
        release_date=None,
    )

    result = ProcessNews(args, gh=mock_gh).run()

    assert result == 0
    assert not news_file.exists()

    content = changelog.read_text(encoding="utf-8")
    assert "* (bzlmod) Added explicit_init_py tag class." in content
    assert "* (cc) Added experimental feature." in content
    assert "## [2.3.0] - 2026-08-07" in content


def test_process_news_pr_number(tmp_path, monkeypatch, mock_gh):
    monkeypatch.chdir(tmp_path)
    changelog = tmp_path / "CHANGELOG.md"
    changelog.write_text(_CHANGELOG_TEMPLATE, encoding="utf-8")

    news_dir = tmp_path / "news"
    news_dir.mkdir()
    news_file = news_dir / "3997.added.md"
    news_file.write_text("(bzlmod) Added explicit_init_py tag class.", encoding="utf-8")

    code_dir = tmp_path / "python" / "extensions"
    code_dir.mkdir(parents=True)
    code_file = code_dir / "config.bzl"
    code_file.write_text(
        """:::{versionadded} VERSION_NEXT_FEATURE
:::
""",
        encoding="utf-8",
    )

    mock_gh.prs[3997] = {
        "files": [
            {"path": "news/3997.added.md"},
            {"path": "python/extensions/config.bzl"},
        ]
    }

    args = argparse.Namespace(
        version="2.3.0",
        targets=["3997"],
        release_date=None,
    )

    result = ProcessNews(args, gh=mock_gh).run()

    assert result == 0
    assert not news_file.exists()

    content = changelog.read_text(encoding="utf-8")
    assert "* (bzlmod) Added explicit_init_py tag class." in content

    updated_code = code_file.read_text(encoding="utf-8")
    assert ":::{versionadded} 2.3.0" in updated_code
    assert "VERSION_NEXT_FEATURE" not in updated_code


def test_process_news_pr_ref_variants(tmp_path, monkeypatch, mock_gh):
    monkeypatch.chdir(tmp_path)
    changelog = tmp_path / "CHANGELOG.md"
    changelog.write_text(_CHANGELOG_TEMPLATE, encoding="utf-8")

    news_dir = tmp_path / "news"
    news_dir.mkdir()
    news_file = news_dir / "3997.added.md"
    news_file.write_text("(bzlmod) Added explicit_init_py tag class.", encoding="utf-8")

    code_file = tmp_path / "feature.py"
    code_file.write_text("FEATURE_VERSION = 'VERSION_NEXT_PATCH'\n", encoding="utf-8")

    mock_gh.prs[3997] = {
        "files": [
            {"path": "news/3997.added.md"},
            {"path": "feature.py"},
        ]
    }

    args = argparse.Namespace(
        version="2.3.0",
        targets=["#3997"],
        release_date=None,
    )

    result = ProcessNews(args, gh=mock_gh).run()

    assert result == 0
    assert not news_file.exists()
    assert "FEATURE_VERSION = '2.3.0'" in code_file.read_text(encoding="utf-8")


def test_process_news_version_normalization(tmp_path, monkeypatch, mock_gh):
    monkeypatch.chdir(tmp_path)
    changelog = tmp_path / "CHANGELOG.md"
    changelog.write_text(_CHANGELOG_TEMPLATE, encoding="utf-8")

    news_dir = tmp_path / "news"
    news_dir.mkdir()
    news_file = news_dir / "3997.added.md"
    news_file.write_text("(bzlmod) Added explicit_init_py tag class.", encoding="utf-8")

    # Pass 2.3 instead of 2.3.0
    args = argparse.Namespace(
        version="2.3",
        targets=[str(news_file)],
        release_date=None,
    )

    result = ProcessNews(args, gh=mock_gh).run()

    assert result == 0
    assert not news_file.exists()

    content = changelog.read_text(encoding="utf-8")
    assert "* (bzlmod) Added explicit_init_py tag class." in content


def test_process_news_multiple_mixed_targets(tmp_path, monkeypatch, mock_gh):
    monkeypatch.chdir(tmp_path)
    changelog = tmp_path / "CHANGELOG.md"
    changelog.write_text(_CHANGELOG_TEMPLATE, encoding="utf-8")

    news_dir = tmp_path / "news"
    news_dir.mkdir()
    file1 = news_dir / "101.added.md"
    file1.write_text("(bzlmod) New feature A.", encoding="utf-8")
    file2 = news_dir / "102.fixed.md"
    file2.write_text("(gazelle) New fix B.", encoding="utf-8")

    code_file = tmp_path / "fix.py"
    code_file.write_text("v = 'VERSION_NEXT_PATCH'", encoding="utf-8")

    mock_gh.prs[102] = {"files": [{"path": "news/102.fixed.md"}, {"path": "fix.py"}]}

    args = argparse.Namespace(
        version="2.3.0",
        targets=[str(file1), "102"],
        release_date=None,
    )

    result = ProcessNews(args, gh=mock_gh).run()

    assert result == 0
    assert not file1.exists()
    assert not file2.exists()

    content = changelog.read_text(encoding="utf-8")
    assert "* (bzlmod) New feature A." in content
    assert "* (gazelle) New fix B." in content
    assert "v = '2.3.0'" in code_file.read_text(encoding="utf-8")


def test_process_news_preserves_target_order(tmp_path, monkeypatch, mock_gh, mocker):
    monkeypatch.chdir(tmp_path)
    changelog = tmp_path / "CHANGELOG.md"
    changelog.write_text(_CHANGELOG_TEMPLATE, encoding="utf-8")

    news_dir = tmp_path / "news"
    news_dir.mkdir()
    file1 = news_dir / "101.added.md"
    file1.write_text("(bzlmod) First feature.", encoding="utf-8")
    file2 = news_dir / "102.added.md"
    file2.write_text("(gazelle) Second feature.", encoding="utf-8")

    mock_gh.prs[102] = {"files": [{"path": "news/102.added.md"}]}

    processed_order = []
    mocker.patch(
        "tools.private.release.process_news.process_pr_target",
        side_effect=lambda target, ver, p, **kwargs: processed_order.append(
            f"PR:{target.pr_num}"
        ),
    )
    mocker.patch(
        "tools.private.release.process_news.process_news_file_target",
        side_effect=lambda target, ver, p, **kwargs: processed_order.append(
            f"FILE:{target.path.name}"
        ),
    )

    # Pass 102 first, then file1
    args = argparse.Namespace(
        version="2.3.0",
        targets=["102", str(file1)],
        release_date=None,
    )

    result = ProcessNews(args, gh=mock_gh).run()

    assert result == 0
    assert processed_order == ["PR:102", "FILE:101.added.md"]


def test_process_news_missing_news_file(tmp_path, monkeypatch, mock_gh):
    monkeypatch.chdir(tmp_path)
    changelog = tmp_path / "CHANGELOG.md"
    changelog.write_text(_CHANGELOG_TEMPLATE, encoding="utf-8")

    args = argparse.Namespace(
        version="2.3.0",
        targets=["news/nonexistent.added.md"],
        release_date=None,
    )

    result = ProcessNews(args, gh=mock_gh).run()

    assert result == 1


def test_process_news_invalid_target(tmp_path, monkeypatch, mock_gh):
    monkeypatch.chdir(tmp_path)
    changelog = tmp_path / "CHANGELOG.md"
    changelog.write_text(_CHANGELOG_TEMPLATE, encoding="utf-8")

    invalid_file = tmp_path / "invalid.txt"
    invalid_file.write_text("Not a news file", encoding="utf-8")

    args = argparse.Namespace(
        version="2.3.0",
        targets=[str(invalid_file)],
        release_date=None,
    )

    result = ProcessNews(args, gh=mock_gh).run()

    assert result == 1


def test_process_news_pr_no_files_found(tmp_path, monkeypatch, mock_gh):
    monkeypatch.chdir(tmp_path)
    changelog = tmp_path / "CHANGELOG.md"
    changelog.write_text(_CHANGELOG_TEMPLATE, encoding="utf-8")

    args = argparse.Namespace(
        version="2.3.0",
        targets=["9999"],
        release_date=None,
    )

    result = ProcessNews(args, gh=mock_gh).run()

    assert result == 1


def test_process_news_version_not_in_changelog(tmp_path, monkeypatch, mock_gh):
    monkeypatch.chdir(tmp_path)
    changelog = tmp_path / "CHANGELOG.md"
    changelog.write_text(_CHANGELOG_TEMPLATE, encoding="utf-8")

    news_dir = tmp_path / "news"
    news_dir.mkdir()
    news_file = news_dir / "3997.added.md"
    news_file.write_text("Some feature", encoding="utf-8")

    args = argparse.Namespace(
        version="3.9.0",
        targets=[str(news_file)],
        release_date=None,
    )

    result = ProcessNews(args, gh=mock_gh).run()

    assert result == 0
    assert not news_file.exists()
    content = changelog.read_text(encoding="utf-8")
    assert "{#v3-9-0}" in content
    assert "## [3.9.0] -" in content
    assert "* Some feature" in content


def test_process_news_creates_version_when_missing_with_custom_release_date(
    tmp_path, monkeypatch, mock_gh
):
    monkeypatch.chdir(tmp_path)
    changelog = tmp_path / "CHANGELOG.md"
    changelog.write_text(_CHANGELOG_TEMPLATE, encoding="utf-8")

    news_dir = tmp_path / "news"
    news_dir.mkdir()
    news_file = news_dir / "3997.added.md"
    news_file.write_text("Some feature", encoding="utf-8")

    args = argparse.Namespace(
        version="2.3.1",
        targets=[str(news_file)],
        release_date="2026-08-15",
    )

    result = ProcessNews(args, gh=mock_gh).run()

    assert result == 0
    assert not news_file.exists()
    content = changelog.read_text(encoding="utf-8")
    assert "{#v2-3-1}" in content
    assert "## [2.3.1] - 2026-08-15" in content
    assert "* Some feature" in content


def test_process_news_creates_version_no_news_files(tmp_path, monkeypatch, mock_gh):
    monkeypatch.chdir(tmp_path)
    changelog = tmp_path / "CHANGELOG.md"
    changelog.write_text(_CHANGELOG_TEMPLATE, encoding="utf-8")

    code_file = tmp_path / "mod.py"
    code_file.write_text("x = 'VERSION_NEXT_PATCH'\n", encoding="utf-8")
    mock_gh.prs[5000] = {"files": [{"path": "mod.py"}]}

    args = argparse.Namespace(
        version="2.3.1",
        targets=["5000"],
        release_date="2026-08-15",
    )

    result = ProcessNews(args, gh=mock_gh).run()

    assert result == 0
    assert "x = '2.3.1'\n" == code_file.read_text(encoding="utf-8")
    content = changelog.read_text(encoding="utf-8")
    assert "{#v2-3-1}" in content
    assert "## [2.3.1] - 2026-08-15" in content
    assert "No notable changes." in content


def test_process_news_cli_parser():
    parser = create_parser()
    args = parser.parse_args(["process-news", "2.3.0", "news/3997.added.md", "3998"])
    assert args.version == "2.3.0"
    assert args.targets == ["news/3997.added.md", "3998"]
    assert args.command == ProcessNews.run_from_args
    assert args.release_date is None

    args_with_flags = parser.parse_args(
        [
            "process-news",
            "2.3.1",
            "news/3997.added.md",
            "--release-date",
            "2026-09-02",
        ]
    )
    assert args_with_flags.release_date == "2026-09-02"

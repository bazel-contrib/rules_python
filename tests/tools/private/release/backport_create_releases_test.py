import argparse

from tools.private.release.backport_create_releases import BackportCreateReleases

# Register pytest fixtures (such as release_tool_env) from release_test_helper
pytest_plugins = ["tests.tools.private.release.release_test_helper"]


def test_create_releases_all_success(release_tool_env, mock_gh):
    # Arrange
    args = argparse.Namespace(issue=123, dry_run=False)
    gh = mock_gh

    # Setup backport issue in mock GH
    backport_body = """* PR: #456
* From version: 1.7
* To version: 1.9

## Tasks

- [x] Verify apply 1.7 | status=success
- [x] Verify apply 1.8 | status=success
- [x] Verify apply 1.9 | status=success
- [ ] Track Release 1.7.2
- [ ] Track Release 1.8.1
- [ ] Track Release 1.9.0"""

    gh.issues[123] = {
        "title": "Backport: #456",
        "body": backport_body,
        "labels": ["type:backport-pr"],
        "number": 123,
        "url": "https://github.com/.../issues/123",
    }

    # Act
    result = BackportCreateReleases(args, gh).run()

    # Assert
    assert result == 0

    # Verify release issues created (IDs 1001, 1002, 1003)
    assert 1001 in gh.issues
    assert 1002 in gh.issues
    assert 1003 in gh.issues

    # 1.7.2 (patch) should not have Tag RC0
    assert gh.issues[1001]["title"] == "Release 1.7.2"
    assert "Tag RC0" not in gh.issues[1001]["body"]
    assert "## Backports\n- [ ] #456" in gh.issues[1001]["body"]

    # 1.9.0 (minor) should have Tag RC0
    assert gh.issues[1003]["title"] == "Release 1.9.0"
    assert "Tag RC0" in gh.issues[1003]["body"]

    # Verify backport issue updated
    expected_updated_backport_body = """* PR: #456
* From version: 1.7
* To version: 1.9

## Tasks

- [x] Verify apply 1.7 | status=success
- [x] Verify apply 1.8 | status=success
- [x] Verify apply 1.9 | status=success
- [x] Track Release 1.7.2 | status=success release_issue=#1001
- [x] Track Release 1.8.1 | status=success release_issue=#1002
- [x] Track Release 1.9.0 | status=success release_issue=#1003"""

    assert gh.issues[123]["body"] == expected_updated_backport_body


def test_create_releases_dependency_blocking(release_tool_env, mock_gh):
    # Arrange
    args = argparse.Namespace(issue=123, dry_run=False)
    gh = mock_gh

    # 1.8 failed, 1.7 and 1.9 succeeded
    backport_body = """* PR: #456
* From version: 1.7
* To version: 1.9

## Tasks

- [x] Verify apply 1.7 | status=success
- [ ] Verify apply 1.8 | status=failed-conflict
- [x] Verify apply 1.9 | status=success
- [ ] Track Release 1.7.2
- [ ] Track Release 1.8.1
- [ ] Track Release 1.9.0"""

    gh.issues[123] = {
        "title": "Backport: #456",
        "body": backport_body,
        "labels": ["type:backport-pr"],
        "number": 123,
        "url": "https://github.com/.../issues/123",
    }

    # Act
    result = BackportCreateReleases(args, gh).run()

    # Assert
    assert result == 0

    # Only 1.9.0 (ID 1001) should be created. 1.7.2 and 1.8.1 are blocked by 1.8 failure.
    assert len(gh.issues) == 2  # Backport issue + 1 release issue
    assert 1001 in gh.issues
    assert gh.issues[1001]["title"] == "Release 1.9.0"

    # Verify backport issue updated with block statuses
    expected_updated_backport_body = """* PR: #456
* From version: 1.7
* To version: 1.9

## Tasks

- [x] Verify apply 1.7 | status=success
- [ ] Verify apply 1.8 | status=failed-conflict
- [x] Verify apply 1.9 | status=success
- [ ] Track Release 1.7.2 | status=error-later-release-did-not-apply
- [ ] Track Release 1.8.1 | status=error-later-release-did-not-apply
- [x] Track Release 1.9.0 | status=success release_issue=#1001"""

    assert gh.issues[123]["body"] == expected_updated_backport_body


def test_create_releases_already_exists(release_tool_env, mock_gh):
    # Arrange
    args = argparse.Namespace(issue=123, dry_run=False)
    gh = mock_gh

    backport_body = """* PR: #456
* From version: 1.7
* To version: 1.7

## Tasks

- [x] Verify apply 1.7 | status=success
- [ ] Track Release 1.7.2"""

    gh.issues[123] = {
        "title": "Backport: #456",
        "body": backport_body,
        "labels": ["type:backport-pr"],
        "number": 123,
        "url": "https://github.com/.../issues/123",
    }

    # Pre-create the release issue to simulate it already existing
    gh.create_issue(
        title="Release 1.7.2",
        body="existing body\n## Backports\n",
        labels=["type: release"],
    )  # Will get ID 1001

    # Act
    result = BackportCreateReleases(args, gh).run()

    # Assert
    assert result == 0
    assert len(gh.issues) == 2

    # Should link existing issue 1001
    expected_updated_backport_body = """* PR: #456
* From version: 1.7
* To version: 1.7

## Tasks

- [x] Verify apply 1.7 | status=success
- [x] Track Release 1.7.2 | status=success release_issue=#1001"""

    assert gh.issues[123]["body"] == expected_updated_backport_body

"""Tests for the release_build_artifacts.yaml workflow."""

from __future__ import annotations

import hashlib
import re
import subprocess
import tarfile
from pathlib import Path

import yaml

from python.runfiles import runfiles


def _load_workflow() -> dict:
    root = runfiles.CreateOrRaise().root() / "rules_python"
    workflow_path = root / ".github/workflows/release_build_artifacts.yaml"
    return yaml.safe_load(workflow_path.read_text(encoding="utf-8"))


def test_matrix_matches_dev_platforms():
    """Each platform in dev/platforms has one matrix job, and vice versa.

    Otherwise, a platform isn't built or is built twice, or a job fails because
    its platform is missing.
    """
    root = runfiles.CreateOrRaise().root() / "rules_python"
    workflow = _load_workflow()
    triples = [
        entry["triple"]
        for entry in workflow["jobs"]["build"]["strategy"]["matrix"]["include"]
    ]
    build_file = (root / "dev/platforms/BUILD.bazel").read_text(encoding="utf-8")
    platforms = re.findall(r'^platform\(\s*name = "([^"]+)",', build_file, re.MULTILINE)

    assert platforms, "No platforms found in dev/platforms/BUILD.bazel"
    # Fail instead of missing a platform whose call doesn't start with its name,
    # e.g. because of a comment.
    calls = re.findall(r"^platform\(", build_file, re.MULTILINE)
    assert len(platforms) == len(calls), "Couldn't parse every platform's name"
    expected = {
        "linux" if "-linux-" in platform else platform for platform in platforms
    }
    # Sets, so that failures list the triples that differ.
    assert set(triples) == expected, "Matrix (left) vs. dev/platforms (right)"
    duplicates = sorted({triple for triple in triples if triples.count(triple) > 1})
    assert not duplicates, f"Triples with more than one job: {duplicates}"


def test_workflow_is_safe_for_presubmit():
    """Verifies that release_build_artifacts.yaml is read-only and never publishes."""
    workflow = _load_workflow()

    # PyYAML parses unquoted `on:` as boolean True in YAML 1.1.
    triggers = workflow.get("on") or workflow.get(True, {})
    assert "pull_request" in triggers

    assert workflow.get("permissions") == {"contents": "read"}

    for job_name, job in workflow["jobs"].items():
        if "permissions" in job:
            assert job["permissions"] == {"contents": "read"}, (
                f"Job '{job_name}' must not request write permissions"
            )
        uses = job.get("uses", "")
        assert "publish" not in uses, f"Job '{job_name}' calls publish workflow: {uses}"
        for step in job.get("steps", []):
            step_uses = step.get("uses", "")
            assert not step_uses.startswith("softprops/action-gh-release"), (
                f"Job '{job_name}' creates/updates a GitHub release"
            )
            step_run = step.get("run", "")
            assert "wheel.publish" not in step_run or "bazel build" in step_run, (
                f"Job '{job_name}' runs wheel.publish instead of building it"
            )


def test_build_jobs_use_buildbuddy_rbe():
    """Verifies that build jobs pass BuildBuddy keys to setup-bazel."""
    workflow = _load_workflow()

    for job_name in ("build", "build_wheel"):
        job = workflow["jobs"][job_name]
        steps = job["steps"]
        setup_steps = [s for s in steps if s.get("name") == "Setup Bazel"]
        assert len(setup_steps) == 1, f"Missing Setup Bazel in {job_name}"
        assert setup_steps[0]["uses"] == "./.github/actions/setup-bazel"
        api_key = setup_steps[0]["with"]["buildbuddy_api_key"]
        assert "secrets.BUILDBUDDY_CAS_ONLY_KEY" in api_key
        assert "secrets.BUILDBUDDY_READ_WRITE_KEY" in api_key


def test_create_archive_and_notes_fetches_and_expands_tag(tmp_path: Path):
    """Verifies create_archive_and_notes.sh fetches missing tags and expands export-subst."""
    script = (
        runfiles.CreateOrRaise().root()
        / "rules_python/.github/workflows/create_archive_and_notes.sh"
    )
    origin = tmp_path / "origin"
    origin.mkdir()

    def git(cwd: Path, *args: str) -> None:
        subprocess.run(
            ["git", *args],
            cwd=cwd,
            check=True,
            capture_output=True,
            text=True,
        )

    git(origin, "init")
    git(origin, "config", "user.email", "test@example.com")
    git(origin, "config", "user.name", "Test User")

    (origin / ".gitattributes").write_text(
        "python/features.bzl export-subst\n", encoding="utf-8"
    )
    (origin / "MODULE.bazel").write_text(
        "TOOL_DEPS_DEV_ONLY = False\n", encoding="utf-8"
    )
    (origin / "python/private").mkdir(parents=True)
    (origin / "python/private/artifacts_manifest.json").write_text(
        "# stub\n", encoding="utf-8"
    )
    (origin / "python/features.bzl").write_text(
        '_VERSION_PRIVATE = "$Format:%(describe:tags=true)$"\n'
        '_COMMIT_PRIVATE = "$Format:%H$"\n',
        encoding="utf-8",
    )
    git(
        origin,
        "add",
        ".gitattributes",
        "MODULE.bazel",
        "python/private/artifacts_manifest.json",
        "python/features.bzl",
    )
    git(origin, "commit", "-m", "Release commit")
    git(origin, "tag", "2.5.0")
    release_sha = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=origin, text=True
    ).strip()

    (origin / "README.md").write_text("later commit on main\n", encoding="utf-8")
    git(origin, "add", "README.md")
    git(origin, "commit", "-m", "Later commit")

    # Clone without tags at the later commit (matches actions/checkout default)
    clone = tmp_path / "clone"
    git(tmp_path, "clone", "--no-tags", str(origin), str(clone))
    (clone / "artifacts_manifest.json").write_text("{}\n", encoding="utf-8")

    # Git < 2.35 (e.g. Debian 11 / Ubuntu 22.04 on Buildkite) does not support
    # %(describe:tags=true) and leaves the literal placeholder unexpanded.
    supports_describe_tags = (
        subprocess.check_output(
            ["git", "log", "-1", "--format=%(describe:tags=true)"],
            cwd=origin,
            text=True,
        ).strip()
        != "%(describe:tags=true)"
    )

    # Presubmit run with no tag argument on an untagged commit uses HEAD SHA
    head_sha = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=clone, text=True
    ).strip()
    subprocess.run([str(script)], cwd=clone, check=True)
    presubmit_archive = clone / f"rules_python-{head_sha}.tar.gz"
    assert presubmit_archive.is_file()
    with tarfile.open(presubmit_archive, "r:gz") as tar:
        features_member = tar.extractfile(
            f"rules_python-{head_sha}/python/features.bzl"
        )
        assert features_member is not None  # type assert
        features_content = features_member.read().decode("utf-8")
        assert f'_COMMIT_PRIVATE = "{head_sha}"' in features_content
        if supports_describe_tags:
            assert '_VERSION_PRIVATE = ""' in features_content

    # Release run fetches and checks out the tag from origin
    git(clone, "checkout", "--", "MODULE.bazel")
    subprocess.run([str(script), "2.5.0"], cwd=clone, check=True)
    archive = clone / "rules_python-2.5.0.tar.gz"
    notes = clone / "release_notes.txt"
    assert archive.is_file()
    assert notes.is_file()

    expected_sha = hashlib.sha256(archive.read_bytes()).hexdigest()
    notes_text = notes.read_text(encoding="utf-8")
    assert expected_sha in notes_text
    assert 'version = "2.5.0"' in notes_text

    with tarfile.open(archive, "r:gz") as tar:
        names = tar.getnames()
        assert "rules_python-2.5.0/README.md" not in names
        features_member = tar.extractfile("rules_python-2.5.0/python/features.bzl")
        assert features_member is not None  # type assert
        features_content = features_member.read().decode("utf-8")
        assert f'_COMMIT_PRIVATE = "{release_sha}"' in features_content
        if supports_describe_tags:
            assert '_VERSION_PRIVATE = "2.5.0"' in features_content

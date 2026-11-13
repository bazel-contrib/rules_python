"""Tests that subworkspace downloader configs stay in sync with root configs."""

from __future__ import annotations

from pathlib import Path

from dev import sync_downloader_configs
from python.runfiles import runfiles

# Maps subworkspace directory names (from SUBWORKSPACE_DIRS) to their runfiles
# path prefixes relative to rf.root().
# LINT.IfChange(subworkspace_dirs)
_SUBWORKSPACE_RUNFILES_PREFIXES = {
    # keep-sorted start
    "gazelle": "rules_python/gazelle",
    "sphinxdocs": "sphinxdocs",
    # keep-sorted end
}
# LINT.ThenChange(//dev/sync_downloader_configs.py:subworkspace_dirs)


def test_subworkspace_files_match_root():
    rf = runfiles.CreateOrRaise()
    root = rf.root()

    assert set(_SUBWORKSPACE_RUNFILES_PREFIXES) == set(
        sync_downloader_configs.SUBWORKSPACE_DIRS
    )

    mismatched: list[str] = []
    for filename in sync_downloader_configs.SYNCED_FILES:
        canonical = (root / f"rules_python/{filename}").read_text(encoding="utf-8")
        for rel_dir, rf_prefix in _SUBWORKSPACE_RUNFILES_PREFIXES.items():
            sub_content = (root / f"{rf_prefix}/{filename}").read_text(encoding="utf-8")
            if sub_content != canonical:
                mismatched.append(f"{rel_dir}/{filename}")

    assert not mismatched, (
        "Out-of-sync downloader configs (run ./dev/sync_downloader_configs.py):\n"
        + "\n".join(sorted(mismatched))
    )


def test_updates_stale_files(tmp_path: Path):
    for filename in sync_downloader_configs.SYNCED_FILES:
        (tmp_path / filename).write_text(f"canonical {filename}\n", encoding="utf-8")
        for rel_dir in sync_downloader_configs.SUBWORKSPACE_DIRS:
            sub = tmp_path / rel_dir / filename
            sub.parent.mkdir(parents=True, exist_ok=True)
            sub.write_text("stale\n", encoding="utf-8")

    updated = sync_downloader_configs.sync_downloader_configs(tmp_path)

    assert updated == [
        "gazelle/downloader_cfg.bazelrc",
        "gazelle/downloader_config.cfg",
        "sphinxdocs/downloader_cfg.bazelrc",
        "sphinxdocs/downloader_config.cfg",
    ]
    for filename in sync_downloader_configs.SYNCED_FILES:
        for rel_dir in sync_downloader_configs.SUBWORKSPACE_DIRS:
            sub = tmp_path / rel_dir / filename
            assert sub.read_text(encoding="utf-8") == f"canonical {filename}\n"
    assert sync_downloader_configs.sync_downloader_configs(tmp_path) == []

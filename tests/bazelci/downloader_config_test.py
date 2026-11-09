"""Verifies that all workspaces use the same Bazel downloader configuration."""

from __future__ import annotations

import os
import pathlib
import posixpath

from dev import sync_downloader_configs
from dev.bazelci import presubmit_flags
from python.runfiles import runfiles

# Paths relative to the repository root.
_EXPECTED_DOWNLOADER_CONFIGS = frozenset(
    {
        "downloader_config.cfg",
        *sync_downloader_configs.SUBWORKSPACE_CONFIGS,
    }
)

_REQUIRED_COMMON_FLAGS = (
    # keep-sorted start
    "common --experimental_repository_downloader_retries=10",
    "common --http_timeout_scaling=10.0",
    # keep-sorted end
)

_DOWNLOADER_CONFIG_FLAG_PREFIX = "common --experimental_downloader_config="


def _repo_roots(rf: runfiles.Runfiles) -> tuple[pathlib.Path, pathlib.Path]:
    root = rf.root()
    return (
        pathlib.Path(str(root / "rules_python/downloader_config.cfg")).parent,
        pathlib.Path(str(root / "sphinxdocs/downloader_config.cfg")).parent,
    )


def _parse_rewrite_sections(
    text: str,
) -> tuple[list[tuple[str, str]], list[tuple[str, str]]]:
    primary: list[tuple[str, str]] = []
    secondary: list[tuple[str, str]] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        assert len(parts) == 3 and parts[0] == "rewrite", (
            f"Invalid rule line: {raw_line!r}"
        )
        pattern, replacement = parts[1], parts[2]
        if replacement.startswith("mirror.bazel.build/"):
            secondary.append((pattern, replacement))
        else:
            primary.append((pattern, replacement))
    return primary, secondary


def test_downloader_config_rules_are_well_formed_and_sorted():
    rf = runfiles.CreateOrRaise()
    canonical = rf.root() / "rules_python" / "downloader_config.cfg"
    primary, secondary = _parse_rewrite_sections(canonical.read_text(encoding="utf-8"))

    assert primary, "Expected at least one primary rewrite rule"
    assert primary == sorted(primary), "Primary rewrite rules must be sorted"
    assert secondary == sorted(secondary), "Secondary rewrite rules must be sorted"

    expected_secondary = [
        (pattern, f"mirror.bazel.build/{replacement}")
        for pattern, replacement in primary
    ]
    assert secondary == expected_secondary, (
        "Secondary mirror.bazel.build rules must match primary rules"
    )


def test_subworkspace_downloader_configs_match_root():
    rf = runfiles.CreateOrRaise()
    main_root, sphinx_root = _repo_roots(rf)
    canonical_path = main_root / "downloader_config.cfg"
    canonical_content = canonical_path.read_text(encoding="utf-8")

    found_configs: dict[str, str] = {}
    for cfg_path in main_root.rglob("downloader_config.cfg"):
        rel = cfg_path.relative_to(main_root).as_posix()
        if rel.startswith("external/"):
            continue
        found_configs[rel] = cfg_path.read_text(encoding="utf-8")
    for cfg_path in sphinx_root.rglob("downloader_config.cfg"):
        rel = f"sphinxdocs/{cfg_path.relative_to(sphinx_root).as_posix()}"
        found_configs[rel] = cfg_path.read_text(encoding="utf-8")

    assert set(found_configs.keys()) == _EXPECTED_DOWNLOADER_CONFIGS, (
        f"Unexpected downloader_config.cfg files: {sorted(found_configs.keys())}"
    )

    mismatched = [
        rel
        for rel, content in sorted(found_configs.items())
        if content != canonical_content
    ]
    assert not mismatched, (
        "Out-of-sync downloader_config.cfg files "
        "(run ./dev/sync_downloader_configs.py): " + ", ".join(mismatched)
    )


def _discover_workspaces(
    main_root: pathlib.Path,
    sphinx_root: pathlib.Path,
) -> dict[str, pathlib.Path]:
    """Discovers all Bazel workspaces in the repository.

    Args:
        main_root: Runfiles path to the main rules_python repository root.
        sphinx_root: Runfiles path to the sphinxdocs repository root.

    Returns:
        Mapping from repository-root-relative workspace path (`.` for root)
        to its directory path in runfiles.
    """
    workspaces: dict[str, pathlib.Path] = {}

    presubmit = main_root / presubmit_flags.PRESUBMIT_PATH
    tasks = presubmit_flags.load_tasks(presubmit.read_text(encoding="utf-8"))
    for task in tasks.values():
        workdir = str(task.get("working_directory", "."))
        if workdir == "sphinxdocs" or workdir.startswith("sphinxdocs/"):
            sub = workdir.removeprefix("sphinxdocs").lstrip("/") or "."
            workspaces[workdir] = sphinx_root / sub
        else:
            workspaces[workdir] = main_root / workdir

    for marker in ("MODULE.bazel", "WORKSPACE"):
        for path in main_root.rglob(marker):
            if not path.is_file() or path.name != marker:
                continue
            rel = path.parent.relative_to(main_root).as_posix()
            if rel == "external" or rel.startswith("external/"):
                continue
            workspaces[rel] = path.parent
        for path in sphinx_root.rglob(marker):
            if not path.is_file() or path.name != marker:
                continue
            sub = path.parent.relative_to(sphinx_root).as_posix()
            rel = "sphinxdocs" if sub == "." else f"sphinxdocs/{sub}"
            workspaces[rel] = path.parent

    return workspaces


def _load_bazelrc_lines(
    rel_ws: str,
    ws_dir: pathlib.Path,
    rc_path: pathlib.Path,
    problems: list[str],
) -> list[str]:
    """Loads non-comment lines from a .bazelrc file, expanding `import` lines.

    Args:
        rel_ws: Repository-root-relative workspace path for error reporting.
        ws_dir: Runfiles path to the active workspace directory.
        rc_path: Runfiles path to the .bazelrc file being read.
        problems: Mutable list collecting validation error messages.

    Returns:
        Flattened list of stripped, non-comment .bazelrc lines.
    """
    lines: list[str] = []
    for raw_line in rc_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if not line.startswith("import "):
            lines.append(line)
            continue
        import_target = line.removeprefix("import ").strip()
        if not import_target.startswith("%workspace%/"):
            problems.append(
                f"{rel_ws}/.bazelrc: import {import_target!r} "
                "must start with %workspace%/"
            )
            continue
        rel_import = import_target.removeprefix("%workspace%/")
        imported_path = pathlib.Path(os.path.normpath(ws_dir / rel_import))
        if not imported_path.is_file():
            problems.append(
                f"{rel_ws}/.bazelrc: imported file {import_target!r} does not exist"
            )
            continue
        lines.extend(_load_bazelrc_lines(rel_ws, ws_dir, imported_path, problems))
    return lines


def test_all_workspaces_configure_same_downloader_config():
    rf = runfiles.CreateOrRaise()
    main_root, sphinx_root = _repo_roots(rf)
    canonical_path = main_root / "downloader_config.cfg"
    canonical_content = canonical_path.read_text(encoding="utf-8")

    workspaces = _discover_workspaces(main_root, sphinx_root)
    # Sanity-check lower bound to ensure runfiles globbing and presubmit
    # discovery did not silently miss workspace directories.
    assert len(workspaces) >= 25, (
        f"Expected at least 25 workspaces, found {len(workspaces)}"
    )

    problems: list[str] = []
    for rel_ws, ws_dir in sorted(workspaces.items()):
        bazelrc = ws_dir / ".bazelrc"
        if not bazelrc.is_file():
            problems.append(f"{rel_ws}: missing .bazelrc")
            continue

        lines = _load_bazelrc_lines(rel_ws, ws_dir, bazelrc, problems)

        for required_flag in _REQUIRED_COMMON_FLAGS:
            if required_flag not in lines:
                problems.append(f"{rel_ws}/.bazelrc: missing '{required_flag}'")

        cfg_lines = [
            (idx, line)
            for idx, line in enumerate(lines)
            if line.startswith(_DOWNLOADER_CONFIG_FLAG_PREFIX)
        ]
        if len(cfg_lines) != 1:
            problems.append(
                f"{rel_ws}/.bazelrc: expected 1 "
                f"{_DOWNLOADER_CONFIG_FLAG_PREFIX}<path> "
                f"line, found {len(cfg_lines)}"
            )
            continue

        cfg_idx, cfg_line = cfg_lines[0]
        try_import_indices = [
            idx for idx, line in enumerate(lines) if line.startswith("try-import ")
        ]
        if try_import_indices and cfg_idx > min(try_import_indices):
            problems.append(
                f"{rel_ws}/.bazelrc: {_DOWNLOADER_CONFIG_FLAG_PREFIX} "
                "must appear before try-import"
            )

        cfg_rel_path = cfg_line.removeprefix(_DOWNLOADER_CONFIG_FLAG_PREFIX)
        resolved_cfg_repo_rel = posixpath.normpath(posixpath.join(rel_ws, cfg_rel_path))
        if resolved_cfg_repo_rel not in _EXPECTED_DOWNLOADER_CONFIGS:
            expected_list = sorted(_EXPECTED_DOWNLOADER_CONFIGS)
            problems.append(
                f"{rel_ws}/.bazelrc: downloader config {cfg_rel_path!r} "
                f"resolves to {resolved_cfg_repo_rel!r}, "
                f"expected one of {expected_list}"
            )
            continue

        resolved_cfg_fs = pathlib.Path(os.path.normpath(ws_dir / cfg_rel_path))
        if not resolved_cfg_fs.is_file():
            problems.append(
                f"{rel_ws}/.bazelrc: resolved config {resolved_cfg_fs} does not exist"
            )
        elif resolved_cfg_fs.read_text(encoding="utf-8") != canonical_content:
            problems.append(
                f"{rel_ws}/.bazelrc: config {resolved_cfg_repo_rel} does not match root"
            )

    assert not problems, "Downloader config issues found:\n" + "\n".join(problems)


def test_sync_downloader_configs(tmp_path: pathlib.Path):
    canonical = tmp_path / "downloader_config.cfg"
    expected_rule = "rewrite ^foo/(.*) bar/$1\n"
    canonical.write_text(expected_rule, encoding="utf-8")

    for rel_sub in sync_downloader_configs.SUBWORKSPACE_CONFIGS:
        sub_path = tmp_path / rel_sub
        sub_path.parent.mkdir(parents=True, exist_ok=True)
        sub_path.write_text("stale\n", encoding="utf-8")

    assert sync_downloader_configs.sync_downloader_configs(tmp_path) is True
    for rel_sub in sync_downloader_configs.SUBWORKSPACE_CONFIGS:
        assert (tmp_path / rel_sub).read_text(encoding="utf-8") == expected_rule

    assert sync_downloader_configs.sync_downloader_configs(tmp_path) is False

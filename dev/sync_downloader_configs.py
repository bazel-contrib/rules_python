#!/usr/bin/env python3

"""Synchronizes downloader_config.cfg across subworkspaces."""

import sys
from pathlib import Path

_SUBWORKSPACE_DIRS = (
    # keep-sorted start
    "examples/build_file_generation",
    "examples/bzlmod",
    "examples/multi_python_versions",
    "examples/pip_parse",
    "examples/pip_parse_vendored",
    "gazelle",
    "gazelle/examples/bzlmod_build_file_generation",
    "sphinxdocs",
    "sphinxdocs/integration_tests/bcr",
    "sphinxdocs/integration_tests/persistent_worker/workspace",
    "tests/integration/bzlmod_lockfile",
    "tests/integration/compile_pip_requirements",
    "tests/integration/compile_pip_requirements_test_from_external_repo",
    "tests/integration/custom_commands",
    "tests/integration/local_toolchains",
    "tests/integration/pip_parse",
    "tests/integration/pip_parse_isolated",
    "tests/integration/prebuilt_toolchain",
    "tests/integration/py_cc_toolchain_registered",
    "tests/integration/runtime_manifests",
    "tests/integration/toolchain_target_settings",
    "tests/integration/unified_pypi",
    "tests/integration/uv_lock",
    "tests/integration/validate_test_main",
    "tests/integration/whl_library",
    # keep-sorted end
)


def main():
    repo_root = Path(__file__).resolve().parent.parent
    canonical = repo_root / "downloader_config.cfg"
    canonical_content = canonical.read_text(encoding="utf-8")

    changed = False
    for rel_dir in _SUBWORKSPACE_DIRS:
        ws_dir = repo_root / rel_dir
        if not ws_dir.is_dir():
            continue
        sub = ws_dir / "downloader_config.cfg"
        old_content = sub.read_text(encoding="utf-8") if sub.exists() else None
        if old_content != canonical_content:
            sub.write_text(canonical_content, encoding="utf-8")
            print(f"Updated {sub.relative_to(repo_root)}")
            changed = True

    if changed:
        sys.exit(1)


if __name__ == "__main__":
    main()

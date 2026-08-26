"""Tests for workflow script permissions and reusable workflow hierarchies."""

from __future__ import annotations

import stat
from pathlib import Path

import yaml

from python.runfiles import runfiles


def test_py_files_with_shebangs_are_executable():
    rf = runfiles.CreateOrRaise()
    workflows_dir = rf.root() / "rules_python/.github/workflows"
    py_files = list(workflows_dir.glob("*.py"))

    assert len(py_files) > 0, f"No Python files found in {workflows_dir}"

    for py_file in py_files:
        lines = py_file.read_text(encoding="utf-8", errors="ignore").splitlines()
        first_line = lines[0] if lines else ""
        if first_line.startswith("#!"):
            mode = py_file.stat().st_mode
            is_executable = bool(mode & stat.S_IXUSR)
            assert is_executable, (
                f"{py_file.name} has a shebang ('{first_line}') but does not "
                f"have executable (+x) permissions (mode: {oct(mode)})"
            )


def _parse_permissions(perms: object) -> dict[str, str] | None:
    if perms is None:
        return None
    if isinstance(perms, str):
        if perms == "read-all":
            return {"_all": "read"}
        if perms == "write-all":
            return {"_all": "write"}
        return {}
    if isinstance(perms, dict):
        return {str(k): str(v) for k, v in perms.items()}
    return {}


def test_reusable_workflow_permissions_hierarchy():
    """Validates that calling workflows grant sufficient permissions."""
    rf = runfiles.CreateOrRaise()
    workflows_dir = rf.root() / "rules_python/.github/workflows"
    workflow_files = list(workflows_dir.glob("*.yaml")) + list(
        workflows_dir.glob("*.yml")
    )

    assert len(workflow_files) > 0, f"No workflow files found in {workflows_dir}"

    permission_levels = {
        "none": 0,
        "read": 1,
        "write": 2,
    }

    workflows_data = {}
    for wf_file in workflow_files:
        content = yaml.safe_load(wf_file.read_text(encoding="utf-8"))
        if isinstance(content, dict):
            workflows_data[wf_file.name] = content

    for caller_name, caller_content in workflows_data.items():
        caller_wf_perms = _parse_permissions(caller_content.get("permissions"))
        jobs = caller_content.get("jobs", {})
        if not isinstance(jobs, dict):
            continue

        for job_name, job_config in jobs.items():
            if not isinstance(job_config, dict):
                continue

            uses = job_config.get("uses")
            if not uses or not isinstance(uses, str):
                continue

            callee_filename = Path(uses).name
            if callee_filename not in workflows_data:
                # External workflow or not in local .github/workflows
                continue

            callee_content = workflows_data[callee_filename]
            callee_wf_perms = _parse_permissions(callee_content.get("permissions"))
            if callee_wf_perms is None:
                # Callee does not define top-level permissions; inherits caller
                continue

            job_perms = _parse_permissions(job_config.get("permissions"))
            effective_caller_perms = (
                job_perms if job_perms is not None else caller_wf_perms
            )

            if effective_caller_perms is None:
                # Caller does not define permissions; uses repo defaults
                continue

            caller_all = effective_caller_perms.get("_all")

            if "_all" in callee_wf_perms:
                required_level = callee_wf_perms["_all"]
                available_level = caller_all or "none"
                req_val = permission_levels.get(required_level, 0)
                avail_val = permission_levels.get(available_level, 0)
                assert avail_val >= req_val, (
                    f"In {caller_name} job '{job_name}': calling "
                    f"'{callee_filename}' requires '{required_level}-all', "
                    f"but caller only allows '{available_level}'."
                )

            for scope, required_level in callee_wf_perms.items():
                if scope == "_all":
                    continue

                if caller_all:
                    available_level = caller_all
                else:
                    available_level = effective_caller_perms.get(scope, "none")

                req_val = permission_levels.get(required_level, 0)
                avail_val = permission_levels.get(available_level, 0)

                assert avail_val >= req_val, (
                    f"In {caller_name} job '{job_name}': calling "
                    f"'{callee_filename}' requires "
                    f"'{scope}: {required_level}', but caller only allows "
                    f"'{scope}: {available_level}'."
                )

"""Checks that .bazelci/presubmit.yml writes flags as mappings of `?` keys."""

from __future__ import annotations

from collections.abc import Mapping

from dev.bazelci import presubmit_flags
from python.runfiles import runfiles


def _find_problems(tasks: Mapping[str, Mapping[str, object]]) -> list[str]:
    problems = []
    for name, task in tasks.items():
        for attr in presubmit_flags.FLAG_ATTRS:
            value = task.get(attr, {})
            if not isinstance(value, dict):
                problems.append(f'{name}: {attr} isn\'t a mapping of `? "--flag"` keys')
            elif any(v is not None for v in value.values()):
                problems.append(f"{name}: {attr} has `?` keys with values")
    return sorted(problems)


def test_presubmit_has_no_flag_problems():
    rf = runfiles.CreateOrRaise()
    presubmit = rf.root() / "rules_python" / presubmit_flags.PRESUBMIT_PATH
    tasks = presubmit_flags.load_tasks(presubmit.read_text(encoding="utf-8"))

    problems = _find_problems(tasks)

    assert not problems, (
        f"Fix these tasks in {presubmit_flags.PRESUBMIT_PATH}:\n" + "\n".join(problems)
    )

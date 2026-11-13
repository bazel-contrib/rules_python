"""Reads the build and test flags of BazelCI presubmit tasks.

BazelCI's bazelci.py loads `.bazelci/presubmit.yml` with `yaml.safe_load`, so
YAML merge keys (`<<:`) resolve the way PyYAML resolves them. It then flattens
each task's `build_flags` and `test_flags` with `flatten()`, which yields a
mapping's keys. This module mirrors that, except that it doesn't expand the
task matrix: matrix values only fill `${{ }}` placeholders, so a task stands
for all of its matrix jobs.

See https://github.com/bazelbuild/continuous-integration/blob/master/buildkite/bazelci.py
"""

from __future__ import annotations

from collections.abc import Iterable, Mapping

import yaml

PRESUBMIT_PATH = ".bazelci/presubmit.yml"
FLAG_ATTRS = (
    # keep-sorted start
    "build_flags",
    "test_flags",
    # keep-sorted end
)


def load_tasks(text: str) -> dict[str, dict[str, object]]:
    """Returns the tasks of a presubmit.yml, with YAML merges resolved."""
    return yaml.safe_load(text)["tasks"]


def diff_tasks(
    old_tasks: Mapping[str, Mapping[str, object]],
    new_tasks: Mapping[str, Mapping[str, object]],
) -> list[str]:
    """Describes how each task's flags changed between two presubmit.yml files.

    Args:
        old_tasks: The tasks before the change, from `load_tasks`.
        new_tasks: The tasks after the change, from `load_tasks`.

    Returns:
        One line per added task, removed task, or changed flags attribute,
        sorted by task. A changed attribute lists removed flags with `-` and
        added flags with `+`, then the new order if the kept flags changed
        order, since Bazel uses a repeated flag's last value.
    """
    lines = []
    for name in sorted(old_tasks.keys() | new_tasks.keys()):
        if name not in new_tasks:
            lines.append(f"{name}: removed")
            continue
        if name not in old_tasks:
            parts = []
            for attr in FLAG_ATTRS:
                flags = " ".join(_task_flags(new_tasks[name], attr)) or "(none)"
                parts.append(f"{attr}: {flags}")
            lines.append(f"{name}: added; {'; '.join(parts)}")
            continue
        for attr in FLAG_ATTRS:
            old_flags = _task_flags(old_tasks[name], attr)
            new_flags = _task_flags(new_tasks[name], attr)
            if old_flags == new_flags:
                continue
            changes = [f"-{flag}" for flag in old_flags if flag not in new_flags]
            changes += [f"+{flag}" for flag in new_flags if flag not in old_flags]
            kept_old = [flag for flag in old_flags if flag in new_flags]
            kept_new = [flag for flag in new_flags if flag in old_flags]
            if kept_old != kept_new:
                changes += ["reordered:", *new_flags]
            lines.append(f"{name}: {attr}: {' '.join(changes)}")
    return lines


def tasks_with_flag(tasks: Mapping[str, Mapping[str, object]], flag: str) -> list[str]:
    """Lists the tasks that pass `flag`, and in which flags attributes."""
    lines = []
    for name in sorted(tasks):
        attrs = [attr for attr in FLAG_ATTRS if flag in _task_flags(tasks[name], attr)]
        if attrs:
            lines.append(f"{name}: {', '.join(attrs)}")
    return lines


def _flatten(value: Iterable[object]) -> list[str]:
    # Like bazelci.py's `flatten()`: keeps strings, expands one level of
    # nested lists, and drops anything else.
    flags = []
    for item in value:
        if isinstance(item, str):
            flags.append(item)
        elif isinstance(item, list):
            flags.extend(item)
    return flags


def _task_flags(task: Mapping[str, object], attr: str) -> list[str]:
    value = task.get(attr, {})
    assert isinstance(value, (dict, list))  # type assert
    return _flatten(value)

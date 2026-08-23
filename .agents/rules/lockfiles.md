---
trigger: glob
description: Rules for updating uv.lock and requirements.txt files
globs:
  - "*requirements*.txt"
  - "*requirements*.in"
  - "uv.lock"
  - "pyproject.toml"
  - "*constraints*.txt"
---

# Lockfile & Dependency Rules

## Updating Lockfiles
* Edit input files (`pyproject.toml` or `requirements.in`), never lockfiles.
* Regenerate via `bazel run <target>:requirements.update` or `:uv_lock.update`.

## Windows Lockfiles (`requirements_windows*.txt`)
* Linux/macOS `.update` targets do not update Windows lockfiles.
* **Never overwrite** Windows lockfiles with non-Windows lockfiles.
* Update only changed package blocks and hashes; preserve Windows dependencies
  (`colorama`) and `# via` comments.

## Dependabot & Dependency Bumps
When dependencies bump, manually synchronize:
* **Retrigger**: Comment `@dependabot recreate` on PRs via `gh pr comment`.
* **Wheel Overrides**: Update wheel filenames in `pip.override(file = "...")`
  (`examples/bzlmod/MODULE.bazel`).
* **Wheel Patches**: Update versions, METADATA hashes/lengths, and RECORD
  entries in `examples/bzlmod/patches/*.patch`.
* **Test Assertions**: Update hardcoded versions and `dist-info` file lists in
  tests (`pip_whl_mods_test.py`, `pip_parse/test.py`, `pip_parse_test.py`).
* **Constraints**: Update conflicting pins in `*constraints*.txt` and rerun
  affected `.update` targets.

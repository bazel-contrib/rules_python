---
name: github-actions-workflows
trigger: glob
globs: [".github/workflows/**"]
---

# GitHub Actions Workflows Rule

* Use the latest version of referenced actions in `.github/workflows/`.
* Preserve `suppress-no-jobs-ran-error` fallback jobs in conditional workflows.
* Pass inputs (e.g. `${{ inputs.issue }}`) directly to commands without
  redundant shell stripping.
* Print console messages using GitHub workflow commands (e.g., `::error::`,
  `::warning::`, `::notice::`, `::group::`).
* **Event Payload Resolution**: For steps that are a single Python script,
  loading event details directly from `$GITHUB_EVENT_PATH` is required (strong
  suggestion otherwise) rather than passing fields via env vars or CLI flags.

## Workflow Python Scripts & Testing
* **Executable Permissions**: Workflow step scripts must have `chmod +x` (mode
  `100755`) and a shebang (e.g. `#!/usr/bin/env python3`).
* **Test Location**: Place workflow tests under `tests/workflows/`.
* **Imports over `sys.path`**: Never alter `sys.path`. Define a `py_library`
  with `imports = ["../../.github/workflows"]` in `tests/workflows/BUILD.bazel`.
* **Functional Design & Fixtures**: Keep scripts functional with one public
  entry point (e.g. `process_comment()`) and private helpers (`_` prefix). Write
  outputs directly when matching actions. Test end-to-end via autouse fixtures
  for GHA env files and API mocks.

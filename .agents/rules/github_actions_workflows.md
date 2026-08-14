---
name: github-actions-workflows
trigger: glob
globs: [".github/workflows/*.yml", ".github/workflows/*.yaml", ".github/*.yaml"]
---

# GitHub Actions Workflows Rule

* Use the latest version of referenced actions in `.github/workflows/`.
* Preserve `suppress-no-jobs-ran-error` fallback jobs in conditional workflows.
* Pass inputs (e.g. `${{ inputs.issue }}`) directly to commands without
  redundant shell parameter stripping or conversions.
* Print console messages using GitHub workflow command syntax (e.g.,
  `::error::`, `::warning::`, `::notice::`, `::group::`).

## Workflow Python Scripts & Testing
* **Test Location**: Place workflow tests under `tests/workflows/`.
* **Imports over `sys.path`**: Never alter `sys.path`. Define a `py_library`
  with `imports = ["../../.github/workflows"]` in `tests/workflows/BUILD.bazel`.
* **Functional Design & Fixtures**: Keep scripts functional with one public
  entry point (e.g. `process_comment()`) and private helpers (`_` prefix). Write
  outputs directly when matching actions. Test end-to-end via autouse fixtures
  for GHA env files and API mocks.

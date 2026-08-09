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

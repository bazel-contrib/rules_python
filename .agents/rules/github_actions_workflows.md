---
name: github-actions-workflows
trigger: glob
globs: [".github/workflows/*.yml", ".github/workflows/*.yaml", ".github/*.yaml"]
---

# GitHub Actions Workflows Rule

* When creating files in `.github/workflows/` (such as `.yml` or `.yaml`
  files), always use the latest version of the referenced GitHub Actions.

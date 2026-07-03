---
name: Release Tracking Issue
about: Checklist for tracking a new release of rules_python.
title: 'Release <version>'
labels: ['type: release']
---
# Release tasks
- [ ] Prepare Release | status=awaiting-preparation
- [ ] Create Release branch
- [ ] Tag RC0
- [ ] Tag Final

## Backports

To request a backport, add it to the checklist below and process it. See [RELEASING.md: How to add backports](https://github.com/bazel-contrib/rules_python/blob/main/RELEASING.md#how-to-add-backports) for details.

---

To manually control the release flow, see the [RELEASING.md: Manual Editing](https://github.com/bazel-contrib/rules_python/blob/main/RELEASING.md#manual-editing-of-tracking-issue) section.

<details>
<summary><b>Available Commands</b></summary>

Comment commands:
- `/prepare`
- `/create-rc`
- `/process-backports`
- `/add-backports`
- `/promote`

See [RELEASING.md](https://github.com/bazel-contrib/rules_python/blob/main/RELEASING.md) for details on how to use them.
</details>

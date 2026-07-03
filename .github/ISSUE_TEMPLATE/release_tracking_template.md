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
- `/prepare`: Auto-determines the next version, creates the tracking issue,
  and sends a preparation PR.
- `/create-rc`: Tags the release branch with a release candidate (RC) and
  publishes it.
- `/process-backports`: Cherry-picks pending backports listed in the
  checklist.
- `/add-backports <PRs>`: Adds PRs to the checklist and processes them.
- `/promote`: Promotes the latest RC to the final release.

See [RELEASING.md](https://github.com/bazel-contrib/rules_python/blob/main/RELEASING.md) for details on how to use them.
</details>

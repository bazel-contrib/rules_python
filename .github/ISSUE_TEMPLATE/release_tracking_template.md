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

<details>
<summary><b>How to add backports</b></summary>

To request a backport:
1. Add a new checklist item under the `## Backports` section.
2. The format must be: `- [ ] #<PR_NUMBER>` (e.g., `- [ ] #1234`).
3. Trigger the [Process Backports Workflow](https://github.com/bazel-contrib/rules_python/actions/workflows/process_backports.yml).
</details>

---
*Maintainers: Automation will react to changes on this issue.*

<details>
<summary><b>Manual Editing</b></summary>

You can manually edit this issue to control the release flow.
The checklist items use metadata suffix: `| key=value key2=value2`.
- **Retry Prepare Release**: Reset to `- [ ] Prepare Release | status=awaiting-preparation`.
- **Force Task Done**: Check the box `- [x]` and add appropriate metadata (e.g. `status=done`).
</details>

<details>
<summary><b>Available Commands</b></summary>

Maintainers can trigger automation by running manual workflows:
- [Process Backports Workflow](https://github.com/bazel-contrib/rules_python/actions/workflows/process_backports.yml)
- [Generate RC Tag Workflow](https://github.com/bazel-contrib/rules_python/actions/workflows/generate_rc.yml)
- [Promote RC to Final Release Workflow](https://github.com/bazel-contrib/rules_python/actions/workflows/promote_rc.yml)
</details>

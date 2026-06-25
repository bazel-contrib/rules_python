---
name: Release Tracking Issue
about: Checklist for tracking a new release of rules_python.
title: 'Release <version>'
labels: ['type:release']
---
# Release tasks
- [ ] Prepare Release | status=awaiting-preparation
- [ ] Create Release branch
- [ ] Tag RC0
- [ ] Tag Final

## Backports
<!-- Items to be cherry-picked into the next RC go here -->

---
*Maintainers: Automation will react to changes on this issue.*

<details>
<summary><b>Available Commands</b></summary>

Maintainers can trigger automation by running manual workflows:
- [Process Backports Workflow](https://github.com/bazel-contrib/rules_python/actions/workflows/process_backports.yml)
- [Generate RC Tag Workflow](https://github.com/bazel-contrib/rules_python/actions/workflows/generate_rc.yml)
- [Promote RC to Final Release Workflow](https://github.com/bazel-contrib/rules_python/actions/workflows/promote_rc.yml)
</details>

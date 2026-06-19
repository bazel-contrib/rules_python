# Plan for Better `rules_python` Release Automation

The current release process (as described in `RELEASING.md`) has good
automation *after* a tag is pushed (`release.yml` handles GitHub Release, BCR
PR, and PyPI publishing). However, the steps *leading up* to the tag push are
largely manual.

This plan outlines a **code-centric, reactive architecture** to automate the
manual preparation, branching, and tagging phases. By moving all core Git and
GitHub CLI logic out of the YAML workflow files and into the Python release
tool (`release.py`), we ensure the release process is robust, locally testable, and
independent of GitHub Actions runner syntax.

## Prerequisite: Release Tracking Issue

Every release is tracked by a dedicated GitHub Issue titled `Release <version>`
(e.g., `Release 0.38.0`), which acts as the single source of truth and state
controller. Release tracking issues are uniquely identified by the
`type:release` label.

*   **Role:** Contains a checklist of completed and remaining steps.
*   **Automation Hub:** Workflows reactively trigger on tracking issue modifications.
*   **Template File:** The issue body structure is decoupled from the codebase and
    resides in `.github/ISSUE_TEMPLATE/release_tracking_template.md`. This is a
    standard GitHub issue template equipped with frontmatter so maintainers can
    easily create tracking issues manually from the GitHub web UI or let the
    automation generate them programmatically.
*   **Available Commands:** Placed at the very end of the issue body inside a
    collapsed HTML `<details>` section to keep the main checklist clean. It
    contains direct web links to the corresponding manual GitHub Action
    workflows.

### Tracking Issue Checklist Syntax

The checklist uses a strict, machine-readable syntax using a pipe `|` separator
to attach space-separated metadata keys to tasks.

#### Main Tasks Checklist

```markdown
# Release tasks
- [ ] Prepare Release | status=pending pr=#1234
- [ ] Create Release branch
- [ ] Tag RC0
- [ ] Tag Final
```

*   **Prepare Release**:
    *   Initial: `- [ ] Prepare Release | status=awaiting-preparation`
    *   Phase 1 PR created: `- [ ] Prepare Release | status=pending pr=#<pr_num>`
    *   PR merged (Phase 2): `- [x] Prepare Release | status=done pr=#<pr_num> commit=<merge_sha>`
*   **Create Release branch**:
    *   Initial: `- [ ] Create Release branch`
    *   Created: `- [x] Create Release branch | status=done branch=release/X.Y commit=<sha>`
*   **Tag RC0**:
    *   Initial: `- [ ] Tag RC0`
    *   Tagged: `- [x] Tag RC0 | status=done tag=vX.Y.Z-rc0 commit=<sha>`
*   **Tag Final**:
    *   Initial: `- [ ] Tag Final`
    *   Tagged: `- [x] Tag Final | status=done tag=vX.Y.Z commit=<sha>`

#### Backports Checklist

Maintainers list PRs to backport under the `## Backports` section:

```markdown
- [x] #1234 | status=done rc=rc1 commit=deadbeef
- [ ] #2345 | status=merge-conflict
- [ ] #3456
```

*   **Pending:** `- [ ] #3456` (or `- [ ] #3456 | status=pending`)
*   **Succeeded Cherry-pick:** `- [x] #1234 | status=done rc=rc<num> commit=<new_short_sha>` (with checkbox marked `- [x]` to show it has been successfully completed).
*   **Conflicting Cherry-pick:** `- [ ] #2345 | status=merge-conflict` (Unchecked, i.e., remains `- [ ]` to indicate it is not complete. Gates subsequent RC tags until resolved or removed).
*   **Unmerged PR Error:** `- [ ] #3456 | status=unmerged-pr` (Unchecked, i.e., remains `- [ ]` to indicate it is not complete. Gates subsequent RC tags until resolved or removed).

---

## Release Tool Commands

The `release.py` script contains all execution logic.

### 1. `determine-next-version`
*   **Description:** Scans git tags and placeholders to determine the next release version.
*   **Inputs:** None.
*   **Outputs:** Prints the version string (e.g. `0.38.0`) to stdout.

### 2. `create-release-issue`
*   **Description:** Creates the tracking issue on GitHub using `release_tracking_template.md`. Exits with code `1` and prints a list of open tracking issue titles/URLs if a release is already in progress.
*   **Inputs:** `--version <version>` (optional).
    *   *Version Resolution:* If not specified, determined automatically by calling `determine_next_version()`.

### 3. `prepare`
*   **Description:** Updates the changelog and placeholders.
*   **Inputs:** `[version]` (optional), `--issue <issue_number>` (optional).
    *   *Version Resolution:* If not specified, determined automatically by calling `determine_next_version()`.
*   **Pre-checks:** 
    *   If `--automation` is set, it first fetches upstream tags/commits and verifies that the workspace has **no uncommitted local edits**, exiting with code `1` if the workspace is dirty.
*   **Automation Flag (`--automation`):** If set, it pushes to branch `prepare-{version}`, opens the preparation PR, and updates the tracking issue's `Prepare Release` task to `- [ ] Prepare Release | status=pending pr=#<pr_num>`.

### 4. `complete-prepare`
*   **Description:** Triggered when the prep PR merges.
*   **Inputs:** `--pr <pr_number>` (required), `--automation`.
*   **Tracking Issue Resolution:** Automatically parses the tracking issue number
    directly from the PR body (which links to the tracking issue).
*   **State Updates:**
    *   Updates `Prepare Release` to: `status=done pr=#<pr> commit=<merge_sha>` (checked).

### 5. `create-release-branch`
*   **Description:** Cuts the release branch.
*   **Inputs:** `--issue <issue_number>` (required), `--automation`.
*   **State Updates:**
    *   Reads the `commit` SHA from the `Prepare Release` task.
    *   Cuts and pushes the `release/X.Y` branch.
    *   Updates `Create Release branch` to: `status=done branch=release/X.Y commit=<sha>` (checked).

### 6. `process-backports`
*   **Description:** Cherry-picks pending, merged backports.
*   **Inputs:** `--issue <issue_number>` (required), `--automation`.
*   **Gating:** Resolves each backport PR. Unmerged PRs are marked as `status=unmerged-pr` (remains unchecked `- [ ]`) and the loop continues. Conflicting cherry-picks are marked as `status=merge-conflict` (remains unchecked `- [ ]`). If any PR is unmerged or cherry-pick fails with a conflict, the tool exits with code `1` at the end of the run.
*   **State Updates:**
    *   Cherry-picks each pending, merged PR using `git cherry-pick -x` in chronological order.
    *   *Success:** Pushes to the release branch, updates the backport line to: `status=done rc=rc<num> commit=<sha>` (with checkbox marked `- [x]` to show it has been successfully completed).
    *   *Conflict:* Aborts, updates the backport line to: `status=merge-conflict` (remains unchecked `- [ ]`).
    *   *Unmerged:* Updates the backport line to: `status=unmerged-pr` (remains unchecked `- [ ]`).

### 7. `create-rc`
*   **Description:** Tags the next RC.
*   **Inputs:** `--issue <issue_number>` (required), `--automation`.
*   **Gating:** Fails if `Prepare Release` or `Create Release branch` are not `status=done`. Fails if any backport in the list is unchecked (`- [ ]`) or does not have `status=done`.
*   **State Updates:**
    *   Queries git tags, increments to the next RC (e.g. `v0.38.0-rc0`), tags, and pushes.
    *   If tagging `rc0`, updates `Tag RC0` to: `status=done tag=vX.Y.Z-rc0 commit=<sha>` (checked).
    *   Announces the tag in an issue comment.

### 8. `promote-rc`
*   **Description:** Promotes the highest RC to final.
*   **Inputs:** `[version]` (optional), `--issue <issue_number>` (optional), `--automation`.
    *   *Version Resolution:* If not specified, determined automatically by finding the next version (which resolves to the active release version if it has not yet been tagged).
    *   *Issue Resolution:* If `--issue` is not specified, it searches for a single open tracking issue with the `type:release` label and matching version in the title. If zero or multiple tracking issues are found, the command errors and exits with code `1`.
*   **State Updates:**
    *   Checks out the highest RC tag, tags `vX.Y.Z`, and pushes.
    *   Always attempts to update the tracking issue's `Tag Final` task to: `status=done tag=vX.Y.Z commit=<sha>` (checked), outputting a warning if the issue cannot be resolved.

---

## GitHub Actions Workflows

### 1. Prepare Release (`prepare_release.yml`)
*   **Trigger:** Manual (`workflow_dispatch`).
*   **Role:** Runs Phase 1.
*   **Command:** `bazel run //tools/private/release -- --automation prepare`.
*   **State Machine:** Transition: `Prepare Release` $\rightarrow$ `status=pending pr=#<pr>`.

### 2. On PR Merged (`on_prepare_release_pr_merged.yml`)
*   **Trigger:** `pull_request: [closed]` (merged, label `release-prepared`).
*   **Role:** Completes Phase 1.
*   **Command:** `bazel run //tools/private/release -- --automation complete-prepare --pr <pr_num>`.
*   **State Machine:** Transition: `Prepare Release` $\rightarrow$ `status=done pr=#<pr> commit=<sha>` (checked).

### 3. Cut Release Branch (`cut_release_branch.yml`)
*   **Trigger:** `issues: [edited]` (filtered by label `type:release`).
*   **Role:** Runs Phase 2 reactively.
*   **Command:** `bazel run //tools/private/release -- --automation create-release-branch --issue <num>`.
*   **State Machine:** Transition: `Create Release branch` $\rightarrow$ `status=done branch=release/X.Y commit=<sha>` (checked).

### 4. Process Backports (`process_backports.yml`)
*   **Trigger:** Manual (`workflow_dispatch`), taking the tracking issue number.
*   **Role:** Runs Phase 2.5 backport processing.
*   **Command:** `bazel run //tools/private/release -- --automation process-backports --issue <num>`.
*   **State Machine:** 
    *   Cherry-pick success: Backport PR $\rightarrow$ `status=done rc=rc<num> commit=<sha>` (checked).
    *   Cherry-pick conflict: Backport PR $\rightarrow$ `status=merge-conflict` (unchecked).
    *   Unmerged PR error: Backport PR $\rightarrow$ `status=unmerged-pr` (unchecked).

### 5. Generate RC Tag (`generate_rc.yml`)
*   **Trigger:** Manual (`workflow_dispatch`), taking the tracking issue number.
*   **Role:** Runs Phase 2.5 RC tagging.
*   **Command:** `bazel run //tools/private/release -- --automation create-rc --issue <num>`.
*   **State Machine:** Transition: If tagging `rc0`, `Tag RC0` $\rightarrow$ `status=done tag=vX.Y.Z-rc0 commit=<sha>` (checked).

### 6. Promote RC to Final (`promote_rc.yml`)
*   **Trigger:** Manual (`workflow_dispatch`), taking the target version.
*   **Role:** Runs Phase 3.
*   **Command:** `bazel run //tools/private/release -- --automation promote-rc <version>`.
*   **State Machine:** Transition: `Tag Final` $\rightarrow$ `status=done tag=vX.Y.Z commit=<sha>` (checked).

---
name: process-dependabot-prs
description: Evaluate open Dependabot PRs against approval criteria, report
  conclusions for user confirmation, fix trivial failures, and merge approved
  PRs using the merge-pr skill
---

@.agents/rules/lockfiles.md

When asked to process, review, or triage Dependabot pull requests:

## 1. Discover and Inspect Open Dependabot PRs

1. Query open Dependabot PRs:
   ```bash
   gh pr list --repo bazel-contrib/rules_python --author "app/dependabot" \
     --state open --json number,title,url,headRefName,mergeable \
     --json mergeStateStatus,statusCheckRollup,files,labels,body,comments \
     --json reviews
   ```
2. For each PR, inspect the diff (`gh pr diff <number> --repo
   bazel-contrib/rules_python`) and check statuses (Buildkite, ReadTheDocs, and
   GitHub Actions).

## 2. Evaluate Against Criteria (OK vs. Problematic)

Classify each PR as **OK**, **OK (with trivial fixes)**, or **Problematic**:

### OK (Safe to Approve and Merge)
* **Routine Patch/Minor Bumps**: Semver-patch or semver-minor updates to
  `/tools/publish`, `/docs`, `dev/`, `sphinxdocs/dev/`, `examples/`,
  `gazelle/examples/`, `tests/`, or `.github/workflows/`.
* **Grouped Security Updates**: `pip` or `uv` group updates confined to version
  pins, hashes, and expected lockfile metadata.
* **Compatible Major Bumps**: Semver-major updates to isolated CI Actions or
  leaf tooling dependencies where release notes show no breaking changes to
  repository usage and CI passes.
* **Trivial Synchronization Failures Only**: CI fails solely due to stale
  derived files or hardcoded version assertions covered in Step 4.

### Problematic (Flag for User Attention)
* **Duplicate or Superseded PRs**: Overlapping `pip` and `uv` group PRs
  modifying the same `*requirements*.txt` files, or PRs where Dependabot
  commented that the update is no longer needed.
* **Python Version Incompatibility**: Updates that drop support for a Python
  version still targeted by the affected lockfile (e.g., `3.10` in
  `requirements_lock_3_10.txt`), or PRs where Dependabot reports an unsupported
  Python version.
* **Lockfile Corruption**: Diffs that strip platform markers, remove
  Windows-only dependencies (e.g., `colorama` in `requirements_windows*.txt`),
  or introduce unexpected transitive dependency churn.
* **Non-Trivial CI or API Breakages**: Core `rules_python` test failures,
  Sphinx/ReadTheDocs build breakages from incompatible plugin changes, or
  breaking CLI/API changes in invoked tools.
* **Suspicious Releases**: Upstream repository URL changes, yanked versions, or
  release notes indicating known regressions.

## 3. Notify User and Request Confirmation

1. **Create Per-PR Analysis Artifacts**: For each evaluated PR, create a
   markdown artifact `dependabot-pr-<number>.md` in the conversation artifact
   directory (`UserFacing: true`, `RequestFeedback: false`) containing:
   - PR number, title, URL, and affected files
   - Diff summary and release notes / changelog highlights
   - CI check status and failure root cause (if any)
   - Evaluation against criteria (**OK**, **OK (with trivial fixes)**, or
     **Problematic**) and recommended action
2. **Prompt User via `ask_question`**: Present one question per PR in a single
   `ask_question` call:
   - Include a clickable `file://` markdown link to that PR's artifact
     (`[dependabot-pr-<number>.md](file:///.../dependabot-pr-<number>.md)`) in
     the `question` text.
   - Provide the following options (prefixing the recommended choice with
     `(Recommended) ` and listing it first):
     - `Approve & merge`
     - `Fix & merge`
     - `Close/skip`
     - `Manually review`
3. Wait for user confirmation before mutating any PR.

## 4. Fix Trivial Failures and Merge Approved PRs

Once the user confirms:

1. **Close Duplicate or Superseded PRs**:
   - When closing/skipping a duplicate or superseded PR, close it and post a
     comment noting which PR supersedes it:
     ```bash
     gh pr close <pr_number> --repo bazel-contrib/rules_python \
       --comment "Superseded by #<superseding_pr_number>."
     ```
2. **Handle Conflicts or Stale Branches**:
   - If a pure Dependabot PR has merge conflicts after another PR merges, run:
     ```bash
     gh pr comment <pr_number> --repo bazel-contrib/rules_python \
       --body "@dependabot recreate"
     ```
3. **Fix Trivial Failures (When Needed)**:
   - Fetch and check out the PR branch:
     ```bash
     git fetch upstream <headRefName>
     git checkout -B <headRefName> upstream/<headRefName>
     ```
   - Apply synchronization fixes per `@.agents/rules/lockfiles.md`:
     - **Gazelle Manifests**: Run `bazel run //:gazelle_python_manifest.update`
       (and `:gazelle_python_manifest_with_types.update` if present) in the
       affected example workspace.
     - **Constraints & Vendored Files**: Update conflicting version pins in
       `*constraints*.txt` (e.g., `examples/pip_parse/constraints_urllib3.txt`,
       `tests/uv/lock/testdata/constraints.txt`),
       `examples/pip_parse_vendored/requirements.bzl`, and
       `tests/uv/lock/testdata/requirements*.txt`.
     - **Wheel Overrides & Patches**: Update wheel filenames in
       `examples/bzlmod/MODULE.bazel` and version/hash/RECORD entries in
       `examples/bzlmod/patches/*.patch`.
     - **Test Assertions**: Update hardcoded package versions and `dist-info`
       lists in `examples/pip_parse/test.py`,
       `examples/pip_parse/pip_parse_test.py`, and
       `examples/bzlmod/whl_mods/pip_whl_mods_test.py`.
   - Verify affected targets pass with `bazel test --config=fast-tests ...`.
   - Commit the fix (never amend or rebase) and push explicitly to upstream:
     ```bash
     git push upstream HEAD:<headRefName>
     ```
4. **Approve the PR**:
   ```bash
   gh pr review <pr_number> --repo bazel-contrib/rules_python --approve
   ```
5. **Merge Using `merge-pr`**:
   - Follow [merge-pr](../merge-pr/SKILL.md) to enqueue the PR (`gh pr merge
     <pr_number> --repo bazel-contrib/rules_python --auto --squash`) and launch
     a `Merge PR Shepherd` subagent to monitor CI, retry flakes, and track the
     merge queue to completion.

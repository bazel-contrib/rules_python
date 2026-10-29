---
name: process-dependabot-prs
description: Continuously monitor for open Dependabot PRs, evaluate them against
  approval criteria, report conclusions for user confirmation, fix trivial
  failures, and merge approved PRs using the merge-pr skill
---

@.agents/rules/lockfiles.md

When asked to process, review, triage, or monitor Dependabot pull requests:

## 1. Start Continuous Background Monitor

1. Check Existing Monitor Process: Check if `monitor_dependabot_prs.py` is
   already running using `pgrep -af "[m]onitor_dependabot_prs.py"` as a
   standalone command (do NOT chain it with `|| ... monitor_dependabot_prs.py`
   in a single shell invocation, as `pgrep -af` will match the parent `bash -c`
   command string).
2. Launch Monitor Daemon: If no monitor process is active, start it via
   `run_command` with `IsDaemon: true` and `WaitMsBeforeAsync: 500` (do NOT
   append a trailing `&`, which causes the shell to exit immediately and kills
   the background process):
   ```bash
   ./.agents/skills/process-dependabot-prs/scripts/monitor_dependabot_prs.py \
     "<your_conversation_id>"
   ```
3. Continuous Wakeup Loop:
   - `monitor_dependabot_prs.py` polls GitHub once every 5 hours (`--interval`)
     and tracks each open Dependabot PR's `(headRefOid, conflict_status)` in
     `scratch/monitored_dependabot_prs.json` under the skill directory.
   - When no new or updated open Dependabot PRs exist, the daemon sleeps without
     waking the agent.
   - Whenever a new Dependabot PR opens, an existing PR is rebased/recreated
     with a new commit SHA (`headRefOid`), or an open PR becomes `CONFLICTING` /
     `DIRTY` after another PR merges, the daemon sends a notification via
     `agentapi send-message` to wake the conversation.
   - Upon starting the daemon—and on every wakeup notification from the
     daemon—execute Steps 2–5 below for any newly discovered or updated open
     Dependabot PRs.
4. Immediate Poll Trigger (`SIGUSR1`):
   - Trigger an immediate poll cycle at any time (for example, right after a
     `Merge PR Shepherd` finishes merging an approved Dependabot PR or after
     refreshing credentials):
     ```bash
     pkill -USR1 -f "monitor_dependabot_prs.py"
     ```
5. Authentication Failures:
   - When `gh` fails due to invalid or expired credentials, keep the background
     monitor process running so it automatically resumes if credentials are
     refreshed incidentally.
   - Prompt the user via `ask_question` so a UI popup alerts them to
     re-authenticate.
   - After the user responds, trigger an immediate poll cycle via `pkill -USR1
     -f "monitor_dependabot_prs.py"`.

## 2. Discover and Inspect Open Dependabot PRs

1. Query open Dependabot PRs:
   ```bash
   gh pr list --repo bazel-contrib/rules_python --author "app/dependabot" \
     --state open --json number,title,url,headRefName,headRefOid,mergeable \
     --json mergeStateStatus,statusCheckRollup,files,labels,body,comments \
     --json reviews
   ```
2. For each new or updated open PR, inspect the diff (`gh pr diff <number>
   --repo bazel-contrib/rules_python`) and check statuses (Buildkite,
   ReadTheDocs, and GitHub Actions).

## 3. Evaluate Against Criteria (OK vs. Problematic)

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
  derived files or hardcoded version assertions covered in Step 5.

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

## 4. Notify User and Request Confirmation

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

## 5. Fix Trivial Failures and Merge Approved PRs

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
   - When a `Merge PR Shepherd` reports that a Dependabot PR has merged, trigger
     an immediate poll (`pkill -USR1 -f "monitor_dependabot_prs.py"`) so any
     remaining open Dependabot PRs that became conflicting are detected and
     recreated right away.

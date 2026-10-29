---
name: github-actions-workflows
trigger: glob
globs: ".github/workflows/**,.github/actions/**,.github/dependabot.yml"
---

# GitHub Actions Workflows Rule

* Use the latest release of referenced actions and downloaded tools in
  `.github/workflows/` and `.github/actions/` (check via
  `gh release view --repo <owner>/<repo>`), targeting supported Node.js
  runtimes (`node24`, not `node20`).
* **Dependabot Coverage for Composite Actions**: When adding a composite action
  directory under `.github/actions/<name>`, add `"/.github/actions/<name>"` to
  the `github-actions` `directories` list in `.github/dependabot.yml` (since
  `directory: "/"` only scans `.github/workflows/`).
* **Verifying Secret-Gated Workflow Steps**: GitHub Actions does not expose
  repository secrets (e.g. `secrets.BUILDBUDDY_CAS_ONLY_KEY`) to `pull_request`
  runs from forks (`origin`). To test secret-gated workflow or composite action
  steps in CI, push the branch to `upstream` and open the PR from
  `bazel-contrib:<branch>`.
* **Use Local Composite Actions (`./.github/actions/setup-bazel`)**: Always use
  local composite action wrappers (such as
  `uses: ./.github/actions/setup-bazel`) instead of invoking upstream actions
  like `bazel-contrib/setup-bazel` directly in `.github/workflows/`. Update
  `.github/actions/setup-bazel/action.yaml` if project defaults or inputs need
  adjustment.
* Preserve `suppress-no-jobs-ran-error` fallback jobs in conditional workflows.
* Pass inputs (e.g. `${{ inputs.issue }}`) directly to commands without
  redundant shell stripping.
* Print console messages using GitHub workflow commands (e.g., `::error::`,
  `::warning::`, `::notice::`, `::group::`).
* **Event Payload Resolution**: For steps that are a single Python script,
  loading event details directly from `$GITHUB_EVENT_PATH` is required (strong
  suggestion otherwise) rather than passing fields via env vars or CLI flags.
* **Preserve `export-subst` in `git archive`**: Always pass a commit or tag ref
  (never a raw `git write-tree` SHA) to `git archive` so `.gitattributes`
  `export-subst` placeholders (such as `$Format:...$` in `python/features.bzl`)
  expand. Use `--add-file` to include generated files.
* **Ref Handling (Tags vs. Commits)**: When a workflow or script processes a
  release tag or a commit (e.g. in presubmit), use that exact tag or commit SHA
  value throughout. Never invent dummy version strings (e.g. `0.0.0-dev`) or
  create synthetic git tags to work around downstream logic.
* **No `--stamp` or `--embed_label` on Pull Requests**: Only pass `--stamp` and
  `--embed_label` on release builds, never on `pull_request` builds, to avoid
  busting remote/RBE caching.
* **Direct `bazel-bin/` Tool Execution**: When a workflow step runs a Bazel
  binary directly from `bazel-bin/<pkg>/<target>` instead of `bazel run`,
  explicitly include `//<pkg>:<target>` in `bazel build` so its `.runfiles` tree
  is materialized.
* **Flat Staging for `actions/upload-artifact` Across Split Transitions**:
  `actions/upload-artifact` strips only the longest common parent directory of
  all matched `path` entries. When uploading files from multiple Bazel
  configurations (`bazel-out/<cfg-1>/...`, `bazel-out/<cfg-2>/...`), stage them
  into a single flat directory first (reading paths from the rule's `.txt`
  manifest) so `<cfg>/...` subdirectories are not preserved in the artifact.

## Security review
* **No `${{ ... }}` in `run:` or `script:` Blocks**: Never interpolate
  `${{ ... }}` expressions (including `${{ secrets.* }}`) directly into `run:`
  shell scripts or `actions/github-script` `script:` bodies, even inside
  quotes. Bind expressions to `env:` variables (strictly step-scoped for
  `secrets.*`) and reference them as quoted shell variables (`"$VAR"`) or
  `process.env.VAR`.
* **Untrusted Git Ref Names (`github.head_ref`, `github.ref_name`)**: Treat
  branch and tag names as untrusted input. Git ref names allow quotes (`'`, `"`)
  and shell metacharacters (`;`, `&`, `|`, `$()`, `` ` ``); reject or guard
  against quotes and `#` before writing refs to `.bazelrc`. Sanitize the value
  in a dedicated prior step (e.g. stripping characters outside
  `[a-zA-Z0-9._/-]`) and output to `$GITHUB_OUTPUT` rather than writing complex
  inline expression guards.
* **CLI Argument & Option-Flag Injection**: Validate untrusted inputs (such as
  slash-command arguments from issue or PR comments) against strict allowlist
  regexes before writing to `$GITHUB_OUTPUT` or passing to tools. Separate
  options from positional arguments with `--` when expanding arrays into CLI
  commands (e.g. `cmd "${ARGS[@]}" -- "${positional[@]}"`).
* **Authorize Before Mutating State**: In comment- or event-triggered workflows,
  verify actor authorization (`author_association` or user allowlist) before
  writing to `$GITHUB_OUTPUT` or `$GITHUB_ENV`, posting reactions, or triggering
  failure-reporting jobs. In failure-reporting jobs, gate on
  `needs.parse_step.result == 'success' && contains(needs.*.result, 'failure')`
  without adding redundant `outputs.command != ''` predicates.
* **Single-Line `$GITHUB_OUTPUT` and `$GITHUB_ENV` Writes**: Reject `\n` and
  `\r` in keys and values before writing `key=value` lines to `$GITHUB_OUTPUT`
  or `$GITHUB_ENV`. In line-anchored regexes over comment or PR bodies, match
  horizontal whitespace (`[ \t]`) and non-linebreak characters (`[^\r\n]`)
  rather than `\s` or `.`.
* **Suppress Untrusted Stdout in Privileged Jobs**: Never echo raw PR bodies,
  titles, or comment bodies to stdout (pass `--quiet` to `grep`, and use
  `printf '%s\n'` instead of `echo` to avoid option-flag parsing and escape
  expansion), preventing `::...::` workflow command injection.

## Workflow Scripts & Testing
* **Separate Script Files (No Inline Scripts)**: Factor non-trivial scripts
  (such as multi-line shell or Python logic) into standalone files (e.g. `.sh`
  or `.py` files) instead of inlining them in workflow YAML steps (`run: |`),
  shell scripts, or command invocations via heredocs (`<< 'EOF'`) or `-c` flags
  (`bash -c`, `python3 -c`). For single-line substitutions in shell scripts, use
  `sed --in-place`.
* **Shell Rules**: Consult the shell rules when writing shell code in workflows
  or action scripts.
* **Executable Permissions**: Workflow step scripts must have `chmod +x` (mode
  `100755`) and a shebang (e.g. `#!/usr/bin/env python3`).
* **Test Location**: Place workflow tests under `tests/workflows/`.
* **Platform Constraints**: Set
  `target_compatible_with = ["@platforms//os:linux"]` on tests for Linux-only
  workflow scripts instead of adding macOS/BSD workarounds.
* **Imports over `sys.path`**: Never alter `sys.path`. Define a `py_library`
  with `imports = ["../../.github/workflows"]` in `tests/workflows/BUILD.bazel`.
* **Functional Design & Fixtures**: Keep scripts functional with one public
  entry point (e.g. `process_comment()`) and private helpers (`_` prefix). Write
  outputs directly when matching actions. Test end-to-end via autouse fixtures
  for GHA env files and API mocks.
* **Git Portability in Workflow Tests**: CI runs on older Linux distributions
  with Git `< 2.35` (e.g. Debian 11, Ubuntu 22.04), where
  `%(describe:tags=true)` is unsupported. Guard assertions on Git $\ge$ 2.35
  format options with a host Git capability check.

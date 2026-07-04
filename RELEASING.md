# Releasing

Start from a clean checkout at `main`.

Before running through the release it's good to run the build and the tests
locally, and make sure CI is passing. You can also test-drive the commit in an
existing Bazel workspace to sanity check functionality.

## Releasing from HEAD

Releases are managed using a semi-automated process centered around a GitHub
Release Tracking Issue and automated workflows triggered by comments or issue edits.

> [!NOTE]
> Comment-based commands must be posted by project maintainers (Owner,
> Member, or Collaborator) and must be on their own line (leading and trailing
> whitespace is ignored).

### Steps

1.  **Prepare the Release**: Run the [Release: Prepare](https://github.com/bazel-contrib/rules_python/actions/workflows/release_prepare.yaml)
    workflow manually. You can trigger it from the GitHub Actions UI or using
    the GitHub CLI:
    ```shell
    gh workflow run release_prepare.yaml --repo bazel-contrib/rules_python
    ```
    This will automatically determine the next version, create a release tracking
    issue, and send a preparation PR.

2.  **Approve and Merge**: Approve and merge the PR. Once merged, a release
    branch will be created automatically.

3.  **Add Backports (if needed)**: If there are backports, add them following
    the [How to add backports](#how-to-add-backports) steps.

4.  **Create an RC**: Comment `/create-rc` on the tracking issue. This will
    automatically process pending backports before creating the RC. If any
    backport fails, the RC creation will abort.

5.  **Iterate**: Repeat steps 3 and 4 until backports and RCs are no longer
    needed.

6.  **Finalize the Release**: Comment `/promote` on the tracking issue to
    finalize the release.


### Manually triggering the release workflow

The release workflow can be manually triggered using the GitHub CLI (`gh`).
This is useful for re-running a release or for creating a release from a
specific commit.

To trigger the workflow, use the `gh workflow run` command:

```shell
gh workflow run release_publish.yaml --ref <TAG>
```

By default, the workflow will publish the wheel to PyPI. To skip this step,
you can set the `publish_to_pypi` input to `false`:

```shell
gh workflow run release_publish.yaml --ref <TAG> -f publish_to_pypi=false
```

### Determining Semantic Version

**rules_python** uses [semantic version](https://semver.org), so releases with
API changes and new features bump the minor, and those with only bug fixes and
other minor changes bump the patch digit.

The release tool will automatically determine the next version number based on
the `VERSION_NEXT_*` placeholders in the codebase. To see what changes are
being accumulated for the next release, review the pending news entries in the
`news/` directory.

## How to add backports

To add backports to an active release, you can use one of the following
methods:

### Method A: Comment on the PR

Comment `/backport` on the PR you wish to backport. This will automatically
add the PR to the active release's backports checklist. Once the PR is merged,
the backports will be automatically processed.

> [!NOTE]
> Commenting `/backport` on an open PR will block further release publishing
> (like creating RCs or promoting) until the PR is merged or manually set to
> status=ignore in the checklist.

### Method B: Comment on the Tracking Issue

Comment `/add-backports <PR_REF> [<PR_REF> ...]` (space or comma separated) on
the tracking issue. The `<PR_REF>` can be a PR number (optionally prefixed with
`#`) or a PR URL (strictly for the configured repository). This will
automatically add the PRs to the checklist and trigger processing.

### Method C: Manual Checklist Update
1.  Manually add checklist items under the `## Backports` section of the
    Release Tracking Issue. The format must be: `- [ ] #<PR_NUMBER>` (e.g.,
    `- [ ] #1234`).
2.  When ready, comment `/process-backports` on the tracking issue to trigger
    processing.

### Method D: Release Tool CLI
You can use the release tool to add backports from your local checkout:
```shell
bazel run //tools/private/release -- add-backports <PR_REF> [<PR_REF> ...]
```
The `<PR_REF>` can be:
*   A PR number (e.g., `124` or `#124`)
*   A PR URL (e.g., `https://github.com/bazel-contrib/rules_python/pull/124`
    or `https://github.com/bazel-contrib/rules_python/pull/124/files`)
*   Only URLs for the configured repository are accepted.

### Failure Behavior
If a backport fails to process (e.g., due to cherry-pick conflicts):
*   The failed backport checklist item will remain unchecked with
    `status=error-<reason>`.
*   You must resolve the conflict manually: checkout the release branch,
    cherry-pick the PR, resolve conflicts, push to remote, and manually check
    the box on the tracking issue checklist with `status=done` metadata.

## Patch release with cherry picks

If a patch release from head would contain changes that aren't appropriate for
a patch release, then the patch release needs to be based on the original
release tag and the patch changes cherry-picked into it.

In this example, release `0.37.0` is being patched to create release `0.37.1`.
The fix being included is commit `deadbeef`.

1. `git checkout release/0.37`
1. `git cherry-pick -x deadbeef`
1. Fix merge conflicts, if any.
1. `git cherry-pick --continue` (if applicable)
1. `git push upstream`

If multiple commits need to be applied, repeat the `git cherry-pick` step for
each.

Once the release branch is in the desired state, comment `/create-rc` on the
tracking issue to tag it, as done with a release from head.

### Announcing releases

We announce releases in the #python channel in the Bazel slack
(bazelbuild.slack.com). Here's a template:

```
Greetings Pythonistas,

rules_python X.Y.Z-rcN is now available
Changelog: https://rules-python.readthedocs.io/en/X.Y.Z-rcN/changelog.html#vX-Y-Z

It will be promoted to stable next week, pending feedback.
```

It's traditional to include notable changes from the changelog, but not
required.

### Re-releasing a version

Re-releasing a version (i.e. changing the commit a tag points to)  is
*sometimes* possible, but it depends on how far into the release process it got.

The two points of no return are:
 * If the PyPI package has been published: PyPI disallows using the same
   filename/version twice. Once published, it cannot be replaced.
 * If the BCR package has been published: Once it's been committed to the BCR
   registry, it cannot be replaced.

If release steps fail _prior_ to those steps, then its OK to change the tag. You
may need to manually delete the GitHub release.

## Manual Editing of Tracking Issue

You can manually edit the Release Tracking Issue to control the release flow.
The checklist items use metadata suffix: `| key=value key2=value2`.

*   **Retry Prepare Release**: Reset the task to `- [ ] Prepare Release | status=awaiting-preparation`.
*   **Force Task Done**: Check the box `- [x]` and add appropriate metadata (e.g. `status=done`).

## Secrets

### PyPI user rules-python

Part of the release process uploads packages to PyPI as the user `rules-python`.
This account is managed by Google; contact rules-python-pyi@google.com if
something needs to be done with the PyPI account.

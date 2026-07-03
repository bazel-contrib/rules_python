# Releasing

Start from a clean checkout at `main`.

Before running through the release it's good to run the build and the tests
locally, and make sure CI is passing. You can also test-drive the commit in an
existing Bazel workspace to sanity check functionality.

## Releasing from HEAD

Releases are managed using a semi-automated process centered around a GitHub
Release Tracking Issue and automated workflows triggered by comments or issue edits.

### Steps

1.  **Prepare the Release**: Manually run the **Release: Prepare** workflow from
    the GitHub Actions UI (or via `gh workflow run`), leaving the `issue` input
    empty. This workflow will:
    *   Automatically determine the next version based on news entries.
    *   Create a new **Release Tracking Issue** (which serves as the central
        hub and checklist for the release).
    *   Create a `prepare-X.Y.Z` branch.
    *   Update `CHANGELOG.md` and version placeholders.
    *   Create a Pull Request with these changes.

2.  **Review and Merge**: Review, approve, and merge the generated Pull Request.
    Once merged:
    *   The **Release: Complete Prepare** workflow will automatically mark the
        "Prepare Release" task as complete on the tracking issue checklist.
    *   The **Release: Create Release Branch** workflow will then automatically
        run (triggered by the issue edit) to cut the `release/X.Y` branch and
        mark the "Create Release branch" task as complete.

3.  **Tag Release Candidate (RC)**: Comment `/create-rc` on the tracking issue.
    This triggers the **Release: Create RC** workflow, which:
    *   Tags the release branch with `X.Y.Z-rcN`.
    *   Triggers the **Release: Publish** workflow to publish the release.

4.  **Announce and Wait**: Announce the RC release (see [Announcing
    releases](#announcing-releases)) and wait for feedback.

5.  **Handle Backports (if needed)**: If bugs need to be fixed in the release:
    *   Cherry-pick the fixes into the release branch (see [Patch release with
        cherry picks]).
    *   Add the backported PRs to the `## Backports` section of the tracking
        issue.
    *   Comment `/process-backports` on the tracking issue to update the checklist.
    *   Comment `/create-rc` again to tag a new RC (e.g. `rc1`).

6.  **Final Release**: Once the RC is stable, promote it to final release by
    manually triggering the **Release: Promote RC** workflow from the GitHub
    Actions UI (or using `gh workflow run`), specifying the final version
    (e.g., `0.38.0`).


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

## Secrets

### PyPI user rules-python

Part of the release process uploads packages to PyPI as the user `rules-python`.
This account is managed by Google; contact rules-python-pyi@google.com if
something needs to be done with the PyPI account.

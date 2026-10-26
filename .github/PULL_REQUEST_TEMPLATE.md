PR Instructions/requirements
* Title uses `type: description` format. See CONTRIBUTING.md for types.
  * Common types are: build, docs, feat, fix, refactor, revert, test
  * Add a news entry file in `news/` as applicable (do not edit `CHANGELOG.md`
    directly)
* Breaking changes include "!" after the type and a "BREAKING CHANGE:"
  section at the bottom.
  See CONTRIBUTING.md for our breaking changes process.
* Body text becomes the commit message upon merge and should be clean and
  concise:
  * Briefly describe *why* this change is being made.
  * Briefly give a high-level overview of *how* the code is changed.
  * Reference issue number, as applicable.
  * Do not include per-file changelogs, test run logs/checklists, or AI
    disclosure metadata in the PR description.
* Update docs and tests, and run `bazel test` and `buildifier` locally prior
  to pushing.
* AI-assisted PRs:
  * After creating the PR, post a separate comment so maintainers understand
    who/what they are interacting with: state the level of human oversight
    (e.g., human-reviewed, semi-autonomous, or autonomous) and explain how
    comments on the PR will be handled (e.g., whether an agent automatically
    monitors and replies, whether a human reviews/approves agent replies before
    posting, or whether the human responds directly).
  * Do not post comments for every CI run or narrate build IDs, commit SHAs,
    or trivial diff details. Reply `PTAL` once CI is passing and ready for
    review.
* Delete these instructions prior to sending the PR

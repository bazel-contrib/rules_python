---
trigger: glob
description: Cross-language code style, control flow, and CLI conventions
globs: "*.py,*.sh,*.cc,*.h,*.go,*.bzl,*.bazel,*.yaml,*.yml"
---

# Code Style Rules

## File Organization & Definition Order
Order definitions within a file as:
1. Global variables / constants
2. Flags / CLI arguments
3. Functions
4. Classes
5. Main

## Control Flow & API Design
* Use early-return guard clauses over deeply nested conditionals.
* When branching on validation modes, make the fall-off `else` the error case
  (fail-closed).
* Accept one form per input (e.g., a file path, not "path or inline content").
  Do not add unrequested modes, filters, knobs, or flag aliases. Create test
  fixture files instead of adding test-only code paths.
* Use module constants directly instead of adding function parameters for values
  that never vary.
* When exposing a private constant (`_NAME`) as public (`NAME`), update all
  internal callers to `NAME` and remove `_NAME = NAME` aliases.
* Omit speculative precondition checks when the underlying operation fails
  clearly on its own.
* Do not accept `None` or add `if x is not None` guards unless `None` is a valid
  domain state.
* Do not write nested comprehensions or comprehensions with multiple `for`
  clauses; use explicit loops.
* Avoid long or complex inline expressions (e.g. multi-condition ternaries,
  compound boolean chains, or dense one-liners). Break them into named
  intermediate variables, prior preparation steps, or explicit statements.

## CLI & Flags
* Comment non-obvious flags (`--force`), non-default schemes, subtle arguments
  (such as significant trailing slashes), and timeouts/thresholds/retries.
* Restrict constrained flag values strictly to the expected tokens (e.g.,
  `true|false`) rather than permissive truthy/falsy sets.
* Include `(AGENTS: requires user confirmation to use)` in `--help` text and
  error messages for CLI flags that bypass safety checks.

## Sorting
* Add `keep-sorted start` and `keep-sorted end` markers on list and dict config
  or registry tables, even when they have a single entry.

## Bulk Logging
* In bulk operations, log a single summary line on success; on failure, list
  each failing item sorted, one per line, with its location and reason.

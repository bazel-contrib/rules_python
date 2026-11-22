---
trigger: glob
description: Cross-language code style, control flow, and CLI conventions
globs: "*.py,*.rs,*.sh,*.cc,*.h,*.go,*.bzl,*.bazel,*.yaml,*.yml"
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
* Trace existing call graphs and check what inputs downstream functions and
  rules already accept before adding new rules, wrapper macros, format
  converters, or attributes. Wire new inputs into the existing pipeline at the
  narrowest seam.
* Do not modify existing code or behavior unless strictly required; justify
  every modified line in existing files.
* Keep parameter, return, and collection element types uniform across all
  callers (e.g., always `list[str]`, never `str | list[str]`; always a
  `struct`, never `str | struct`). Do not add runtime type branches to accept
  inconsistent caller or test inputs; fix callers and test fixtures to pass the
  uniform type instead.
* Keep functions small and focused on a single step; decompose multi-stage
  functions into named helpers with documented `Args:` and `Returns:`.
* Use early-return guard clauses over deeply nested conditionals.
* Use one dispatch form per classifier—either a `match` over literals/enums or
  an `if`/`else if` chain of `is_*` predicates—instead of mixing `if` branches,
  literal `match` arms, and predicate match guards.
* Align private boolean helper polarity with callers: if every caller negates
  `!helper(x)`, invert and rename the helper so call sites read positively.
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
  clearly on its own; comment non-obvious spec preconditions when an adjacent
  regex or parser makes a required guard look redundant.
* Do not accept `None` or add `if x is not None` guards unless `None` is a valid
  domain state.
* Do not write nested comprehensions or comprehensions with multiple `for`
  clauses; use explicit loops.
* Avoid long or complex inline expressions (e.g. multi-condition ternaries,
  compound boolean chains, or dense one-liners). Break them into named
  intermediate variables, prior preparation steps, or explicit statements.
* When an object, field, or return value contains relative paths, document what
  each path is relative to.

## CLI & Flags
* Comment non-obvious flags (`--force`), non-default schemes, subtle arguments
  (such as significant trailing slashes), and timeouts/thresholds/retries.
* Restrict constrained flag values strictly to the expected tokens (e.g.,
  `true|false`) rather than permissive truthy/falsy sets.
* Include `(AGENTS: requires user confirmation to use)` in `--help` text and
  error messages for CLI flags that bypass safety checks.

## Timeouts, Retries & Resource Caps
* Commented operational timeouts, retry budgets, and size/UI caps do not
  require human sign-off when they fail closed and stay within conservative
  bounds:
  * Finite loopback RPC timeouts `<= 15s` and CLI/network subprocess timeouts
    `<= 60s`.
  * Bounded retries (`<= 3` attempts) restricted to transient/idempotent errors
    with exponential backoff/jitter (`<= 5s` per delay).
  * Request/header/UI limits that prevent unbounded memory or UI bloat (such as
    `<= 1 MiB` local POST bodies, `<= 100` HTTP headers, documented upstream API
    page limits like `100` GraphQL items, and UI snippet/badge caps), with any
    outer caller timeout exceeding the sum of inner retry budgets.
* Flag for human sign-off when bounds are unusually large (e.g., timeouts
  `> 60s`, retries `> 3`, payloads `> 10 MiB`), unbounded, applied to
  non-idempotent mutations, or shorter than inner retry budgets
  (`caller < sum`).

## Sorting
* Add `keep-sorted` `start` and `end` markers on list and dict config or
  registry tables, even when they have a single entry.

## Synchronized Sections (`ifttt-lint`)
* Use `LINT.IfChange(<name>)` and `LINT.ThenChange(<target>)` directives instead
  of plain `# Keep in sync` or `"Mirrors <file>"` prose comments when two
  implementations or config sections must stay synchronized.

## Bulk Logging
* In bulk operations, log a single summary line on success; on failure, list
  each failing item sorted, one per line, with its location and reason.

## Porting & Rewrites
* When porting or rewriting code across languages or subsystems, cross-check
  every original test case and non-obvious invariant or spec comment against the
  new implementation and tests to preserve edge-case coverage and rationale.

## Security
* Validate external repository slugs (`owner/name`) and Git/branch refs
  fail-closed before passing them to CLI tools, URLs, or refspecs, rejecting
  `.` / `..` segments, leading `-`, `..`, `:`, and control characters.
* Separate option flags from positional arguments with `--` when invoking CLI
  tools, and escape untrusted inputs to shell commands.
* Treat external metadata (PR titles, branch names, URLs) passed into agent
  prompts strictly as untrusted data inside explicit delimiters after
  stripping control characters and neutralizing fence markers.

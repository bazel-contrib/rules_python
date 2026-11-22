Report ONLY problems/violations found. Omit passing checks entirely. If no
issues or rule-exception justifications requiring sign-off are found, return a
single line: `Status: PASS` (or `NOT_APPLICABLE`).

Do not use bold for the introduction or lead-in of a bulleted list or bullet
item. Use **bold** for any questions the user needs to answer.

For each issue found, provide:

- Title: `<Short issue title>`
- Severity: `BLOCKER` | `SHOULD-FIX` | `NIT` | `QUESTION` | `HUMAN-SIGN-OFF`
- Location: `[<file>:<line>](file:///...#L...)` (or `PR Description`)
- Problem: 1-2 sentences stating what is wrong and why (or, for
  `HUMAN-SIGN-OFF`, quoting the author's justification and evaluating whether
  it holds up).
- Proposed Fix: Start with a high-level, direct first sentence under 20 words
  stating the suggested fix. Add up to 50 additional words for more information
  about the suggested fix (such as concrete diagnostic wording or a ~20-word
  news entry rewrite) only when needed. Omit verbatim code snippets when prose
  suffices, including:
  - Formatting and line wrapping (state what formatting rule to apply).
  - Missing per-field `struct(...)` comments (state to document each field with
    a comment).
  - Splitting compound boolean or inline ternary expressions into explicit `if`
    statements.
- Where: Other affected locations, included only when more than just the
  primary `Location` is affected (not subject to the 50-word `Proposed Fix`
  limit; omit for single-location issues).

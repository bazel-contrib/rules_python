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
- Proposed Fix: Concrete code snippet, diff, or replacement text.
- Draft Comment: Ready-to-post comment in user's voice, phrased mechanically
  with minimal prose and structured as (include `Where:` only when more than
  just the commented location is affected):
  ```markdown
  <brief/concise description of issue>

  Suggested fix: <fix, under 20 lines / 10 sentences>

  Where: <other locations where this is applicable, if more than just the
  commented location>
  ```
  Keep `<brief/concise description of issue>` to 1–2 short, direct sentences
  (no multi-clause "wall of text" paragraphs, parenthetical `e.g.` scenario
  lists, or `"conversely..."` chains). When suggesting wording for an
  error/failure message, comment, or short snippet, include the concrete
  suggested text in `Suggested fix:` inside `Draft Comment` (not only in
  `Proposed Fix`). Avoid wrapping lists of visually distinct identifiers (such
  as `UPPER_SNAKE_CASE` constants) in individual backticks so rendered text
  does not jump repeatedly into and out of code formatting, and never wrap the
  entire comment in outer backticks.

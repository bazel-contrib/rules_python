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
- Draft Comment: Ready-to-post comment in user's voice.

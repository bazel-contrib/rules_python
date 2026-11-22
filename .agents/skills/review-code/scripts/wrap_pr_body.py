#!/usr/bin/env python3
"""Wrap GitHub PR description prose at 72 columns via ``gh pr edit``.

Fetches the latest PR body immediately before editing, strips disallowed
control characters and ANSI escapes, deterministically wraps Markdown prose
while preserving author wording, URLs, Markdown links, fenced code blocks,
and Markdown tables, and verifies non-whitespace token equivalence prior to
applying ``gh pr edit``.

Usage:
  .agents/skills/review-code/scripts/wrap_pr_body.py [--repo=OWNER/REPO] \\
      [--dry-run] -- <pr_number>

Prints a single JSON status line on stdout without echoing untrusted PR text.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from collections.abc import Sequence

_DEFAULT_REPO = "bazel-contrib/rules_python"
_WRAP_WIDTH = 72
# Bound gh CLI network calls so stalled requests fail closed within code-style limits.
_GH_TIMEOUT_SECONDS = 30
_CONTROL_CHAR_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]")
_ANSI_ESCAPE_RE = re.compile(
    r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)"
)
_REPO_SLUG_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\Z")
_FENCE_RE = re.compile(r"^\s{0,3}(?:(`{3,})[^`\n]*|(~{3,}).*)\Z")
_QUOTE_PREFIX_RE = re.compile(r"^((?:\s{0,3}>\s?)+)(.*)$")
_LIST_ITEM_RE = re.compile(r"^(\s*(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?)(.*)$")
_ATX_HEADING_RE = re.compile(r"^\s{0,3}#{1,6}(?:\s|$)")
_SETEXT_UNDERLINE_RE = re.compile(r"^\s{0,3}(?:=+|-+)\s*\Z")
_THEMATIC_BREAK_RE = re.compile(r"^\s{0,3}([-*_])(?:\s*\1){2,}\s*\Z")
_LINK_REF_RE = re.compile(r"^\s{0,3}\[[^\]]+\]:\s+\S+")
_TABLE_DELIM_RE = re.compile(
    r"^\s*\|?\s*:?-{2,}:?\s*(?:\|\s*:?-{2,}:?\s*)+\|?\s*\Z"
    r"|^\s*\|\s*:?-{2,}:?\s*\|?\s*\Z"
)
_HTML_COMMENT_START_RE = re.compile(r"^\s{0,3}<!--")
_HTML_BLOCK_LINE_RE = re.compile(
    r"^\s{0,3}(?:<!--|</?(?:details|summary|table|thead|tbody|tr|th|td|pre|"
    r"div|img|p|br|hr)\b)",
    re.IGNORECASE,
)
_ALERT_LINE_RE = re.compile(r"^\[!(?:NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*\Z")
_BARE_URL_RE = re.compile(r"https?://\S+")
_SPACE_HARD_BREAK_RE = re.compile(r"  +\Z")
_HARD_BREAK_RE = re.compile(r"(?:  +|\\)\Z")
_LEADING_QUOTES_RE = re.compile(r"^(?:\s{0,3}>\s?)+")
_BLOCK_START_ATOMS = frozenset({">", "-", "*", "+"})
_BLOCK_START_RE = re.compile(r"^(?:>+|#{1,6}|\d+[.)]|-+|[*_]{3,}|=+)\Z")


def build_parser() -> argparse.ArgumentParser:
    """Builds the CLI argument parser.

    Returns:
        Configured ``argparse.ArgumentParser`` for ``wrap_pr_body``.
    """
    parser = argparse.ArgumentParser(
        description=("Wrap GitHub PR description prose at 72 columns safely via gh.")
    )
    parser.add_argument(
        "--repo",
        default=_DEFAULT_REPO,
        help="GitHub repository slug in owner/name format",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Check whether wrapping is needed without editing the PR",
    )
    parser.add_argument(
        "pr_number",
        type=int,
        help="Pull request number to inspect and wrap",
    )
    return parser


def sanitize_text(text: str) -> str:
    """Normalizes newlines and strips ANSI escapes and C0/C1 control chars.

    Args:
        text: Untrusted raw text to sanitize.

    Returns:
        Sanitized UTF-8 string safe for Markdown wrapping and error notes.
    """
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    no_ansi = _ANSI_ESCAPE_RE.sub("", normalized)
    return _CONTROL_CHAR_RE.sub("", no_ansi)


def validate_repo_slug(repo: str) -> str:
    """Validates an ``owner/name`` repository slug fail-closed.

    Args:
        repo: Repository slug in ``owner/name`` format.

    Returns:
        The validated ``owner/name`` slug.
    """
    if (
        not _REPO_SLUG_RE.match(repo)
        or ".." in repo
        or ":" in repo
        or any(ord(ch) < 32 or ord(ch) == 127 for ch in repo)
    ):
        raise ValueError(f"Invalid repository slug: {repo!r}")
    owner, name = repo.split("/", 1)
    if (
        owner in {".", ".."}
        or name in {".", ".."}
        or owner.startswith("-")
        or name.startswith("-")
    ):
        raise ValueError(f"Invalid repository slug: {repo!r}")
    return repo


def validate_pr_number(pr_number: int) -> int:
    """Validates that ``pr_number`` is a positive integer.

    Args:
        pr_number: Candidate pull request number.

    Returns:
        The validated positive integer pull request number.
    """
    if pr_number <= 0:
        raise ValueError(f"Pull request number must be positive: {pr_number}")
    return pr_number


def _match_inline_code(text: str, start: int) -> int | None:
    """Finds the exclusive end index of a backtick span starting at ``start``.

    Args:
        text: Paragraph string.
        start: Index of the opening backtick.

    Returns:
        End index after matching closing backticks, or ``None`` if unmatched.
    """
    tick_end = start
    while tick_end < len(text) and text[tick_end] == "`":
        tick_end += 1
    tick_len = tick_end - start
    pos = tick_end
    while pos < len(text):
        if text[pos] == "`":
            close_end = pos
            while close_end < len(text) and text[close_end] == "`":
                close_end += 1
            if close_end - pos == tick_len:
                return close_end
            pos = close_end
        else:
            pos += 1
    return None


def _match_markdown_link(text: str, start: int) -> int | None:
    """Finds the exclusive end index of an inline or reference Markdown link.

    Args:
        text: Paragraph or line string.
        start: Index of the opening ``[``.

    Returns:
        End index after ``](...)`` or ``][...]``, or ``None`` if not a link.
    """
    n = len(text)
    depth = 0
    pos = start
    while pos < n:
        ch = text[pos]
        if ch == "\\" and pos + 1 < n:
            pos += 2
            continue
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                break
        pos += 1
    else:
        return None

    after = pos + 1
    if after >= n:
        return None
    if text[after] == "(":
        paren_depth = 0
        q = after
        while q < n:
            ch = text[q]
            if ch == "\\" and q + 1 < n:
                q += 2
                continue
            if ch == "(":
                paren_depth += 1
            elif ch == ")":
                paren_depth -= 1
                if paren_depth == 0:
                    return q + 1
            q += 1
        return None
    if text[after] == "[":
        q = after + 1
        while q < n:
            ch = text[q]
            if ch == "\\" and q + 1 < n:
                q += 2
                continue
            if ch == "]":
                return q + 1
            q += 1
    return None


def _match_autolink(text: str, start: int) -> int | None:
    """Finds the exclusive end index of a ``<https://...>`` or ``<http://...>`` link.

    Args:
        text: Paragraph or line string.
        start: Index of the opening ``<``.

    Returns:
        End index after closing ``>``, or ``None`` if not a URL autolink.
    """
    if text.startswith("<http://", start) or text.startswith("<https://", start):
        close = text.find(">", start + 1)
        if close != -1 and not any(ch.isspace() for ch in text[start:close]):
            return close + 1
    return None


def _tokenize_prose(text: str) -> list[str]:
    """Splits prose into wrapping atoms without breaking links or code spans.

    Args:
        text: Normalized paragraph prose string.

    Returns:
        Ordered list of unbreakable wrapping atoms.
    """
    atoms: list[str] = []
    n = len(text)
    i = 0
    while i < n:
        while i < n and text[i].isspace():
            i += 1
        if i >= n:
            break
        start = i
        buf: list[str] = []
        while i < n and not text[i].isspace():
            ch = text[i]
            if ch == "`":
                end = _match_inline_code(text, i)
                if end is not None:
                    buf.append(text[i:end])
                    i = end
                    continue
                while i < n and text[i] == "`":
                    buf.append("`")
                    i += 1
                continue
            if ch == "[":
                end = _match_markdown_link(text, i)
                if end is not None:
                    buf.append(text[i:end])
                    i = end
                    continue
            if ch == "<":
                end = _match_autolink(text, i)
                if end is not None:
                    buf.append(text[i:end])
                    i = end
                    continue
            buf.append(ch)
            i += 1
        if buf or i > start:
            atoms.append("".join(buf))
    return atoms


def _is_block_starter(atom: str) -> bool:
    """Checks whether placing ``atom`` at line start can start a Markdown block.

    Args:
        atom: Single wrapping atom token.

    Returns:
        ``True`` if placing ``atom`` at column 0 could start a Markdown block.
    """
    if atom.startswith(">"):
        return True
    return atom in _BLOCK_START_ATOMS or bool(_BLOCK_START_RE.match(atom))


def _wrap_atoms(
    atoms: Sequence[str],
    initial_indent: str,
    subsequent_indent: str,
    width: int,
) -> list[str]:
    """Wraps atoms greedily at ``width`` while avoiding block-starter line starts.

    Args:
        atoms: Ordered prose wrapping atoms.
        initial_indent: Prefix for the first emitted line.
        subsequent_indent: Prefix for continuation lines.
        width: Target column width for wrapped prose.

    Returns:
        Wrapped lines without trailing newlines.
    """
    if not atoms:
        return [initial_indent.rstrip()] if initial_indent.strip() else [""]
    lines: list[str] = []
    current: list[str] = []
    prefix = initial_indent
    line_len = len(prefix)
    for atom in atoms:
        if not current:
            current.append(atom)
            line_len += len(atom)
            continue
        if line_len + 1 + len(atom) <= width:
            current.append(atom)
            line_len += 1 + len(atom)
            continue
        if _is_block_starter(atom):
            if len(current) > 1 and not _is_block_starter(current[-1]):
                carried = current.pop()
                lines.append(prefix + " ".join(current))
                prefix = subsequent_indent
                current = [carried, atom]
                line_len = len(prefix) + len(carried) + 1 + len(atom)
                continue
            current.append(atom)
            line_len += 1 + len(atom)
            continue
        lines.append(prefix + " ".join(current))
        prefix = subsequent_indent
        current = [atom]
        line_len = len(prefix) + len(atom)
    lines.append(prefix + " ".join(current))
    return lines


def _strip_excluded_links_and_urls(line: str) -> str:
    """Removes Markdown links, autolinks, and bare URLs for prose-width checks.

    Args:
        line: Single Markdown prose line.

    Returns:
        Line text with links and URLs removed so only surrounding prose counts.
    """
    out: list[str] = []
    i = 0
    n = len(line)
    while i < n:
        if line[i] == "[":
            end = _match_markdown_link(line, i)
            if end is not None:
                i = end
                continue
        if line[i] == "<":
            end = _match_autolink(line, i)
            if end is not None:
                i = end
                continue
        if line.startswith(("http://", "https://"), i):
            match = _BARE_URL_RE.match(line, i)
            if match is not None:
                i = match.end()
                continue
        out.append(line[i])
        i += 1
    return "".join(out)


def _line_exceeds_prose_width(line: str) -> bool:
    """Checks whether ``line`` exceeds ``_WRAP_WIDTH`` outside links and URLs.

    Args:
        line: Single raw Markdown prose line.

    Returns:
        ``True`` if non-link, non-URL prose extends beyond ``_WRAP_WIDTH``.
    """
    if len(line) <= _WRAP_WIDTH:
        return False
    prose_only = _strip_excluded_links_and_urls(line).rstrip()
    return len(prose_only) > _WRAP_WIDTH


def _is_verbatim_single_line(line: str) -> bool:
    """Checks whether ``line`` is standalone Markdown syntax kept verbatim.

    Args:
        line: Inner line text without outer blockquote prefix.

    Returns:
        ``True`` for headings, thematic breaks, link refs, HTML, alerts, or pipes.
    """
    return bool(
        _ATX_HEADING_RE.match(line)
        or _THEMATIC_BREAK_RE.match(line)
        or _LINK_REF_RE.match(line)
        or _HTML_BLOCK_LINE_RE.match(line)
        or _ALERT_LINE_RE.match(line)
        or line.lstrip().startswith("|")
    )


def _split_quote_lines(lines: Sequence[str]) -> list[tuple[str, str]]:
    """Splits each line into its blockquote prefix and inner Markdown text.

    Args:
        lines: Sanitized input lines.

    Returns:
        List of ``(blockquote_prefix, inner_line)`` tuples.
    """
    split: list[tuple[str, str]] = []
    for line in lines:
        match = _QUOTE_PREFIX_RE.match(line)
        if match:
            split.append((match.group(1), match.group(2)))
        else:
            split.append(("", line))
    return split


def _is_table_header(entries: Sequence[tuple[str, str]], idx: int) -> bool:
    """Checks whether line ``idx`` starts a pipe-delimited Markdown table.

    Args:
        entries: Quote-split ``(qprefix, inner_line)`` entries.
        idx: Starting line index to inspect.

    Returns:
        ``True`` if ``idx`` and ``idx + 1`` form a Markdown table header.
    """
    if idx + 1 >= len(entries):
        return False
    q0, line0 = entries[idx]
    q1, line1 = entries[idx + 1]
    if q0 != q1 or "|" not in line0:
        return False
    return bool(_TABLE_DELIM_RE.match(line1))


def _wrap_paragraph_block(
    entries: Sequence[tuple[str, str]],
    initial_indent: str,
    subsequent_indent: str,
    raw_lines: Sequence[str],
) -> tuple[list[str], bool]:
    """Wraps a paragraph or list-item block if any line exceeds prose width.

    Args:
        entries: Quote-split ``(qprefix, inner_line)`` entries for the block.
        initial_indent: Inner indent/marker prefix for line 0.
        subsequent_indent: Inner indent prefix for continuation lines.
        raw_lines: Original unsplit lines used for width checking and fallback.

    Returns:
        Tuple of ``(output_lines, changed)``.
    """
    baseline = list(raw_lines)
    if not any(_line_exceeds_prose_width(line) for line in baseline):
        return baseline, False

    qprefix = entries[0][0]
    inner_width = max(1, _WRAP_WIDTH - len(qprefix))
    parts = [entries[0][1].lstrip()]
    for _, inner in entries[1:]:
        parts.append(inner.strip())
    joined = " ".join(part for part in parts if part)
    atoms = _tokenize_prose(joined)
    if not atoms:
        return baseline, False

    wrapped_inner = _wrap_atoms(atoms, initial_indent, subsequent_indent, inner_width)
    wrapped = [qprefix + line for line in wrapped_inner]
    if _SPACE_HARD_BREAK_RE.search(baseline[-1]):
        wrapped[-1] += "  "
    if wrapped == baseline:
        return baseline, False
    return wrapped, True


def _consume_prose_run(
    entries: Sequence[tuple[str, str]],
    start: int,
    qprefix: str,
    allow_indented: bool,
) -> int:
    """Scans a contiguous wrappable prose run starting at ``start``.

    Args:
        entries: Quote-split ``(qprefix, inner_line)`` entries.
        start: First line index of the prose block.
        qprefix: Expected blockquote prefix for lines in this block.
        allow_indented: Whether 4-space/tab indented lines belong to the run.

    Returns:
        Exclusive end index of the prose run.
    """
    idx = start + 1
    while idx < len(entries):
        nq, nline = entries[idx]
        if nq != qprefix or not nline.strip():
            break
        if (
            _FENCE_RE.match(nline)
            or _LIST_ITEM_RE.match(nline)
            or nline.lstrip().startswith(">")
            or _is_verbatim_single_line(nline)
            or _is_table_header(entries, idx)
        ):
            break
        if not allow_indented and (nline.startswith("    ") or nline.startswith("\t")):
            break
        if _HARD_BREAK_RE.search(entries[idx - 1][1]):
            break
        if not allow_indented and idx + 1 < len(entries):
            if entries[idx + 1][0] == qprefix and _SETEXT_UNDERLINE_RE.match(
                entries[idx + 1][1]
            ):
                break
        idx += 1
    return idx


def _consume_fenced_block(
    entries: Sequence[tuple[str, str]], start: int, fence: str
) -> tuple[list[str], int]:
    """Consumes a fenced code block verbatim starting at ``start``.

    Args:
        entries: Quote-split ``(qprefix, inner_line)`` entries.
        start: Opening fence line index.
        fence: Opening backtick or tilde fence sequence.

    Returns:
        Tuple of ``(verbatim_lines, next_index)``.
    """
    qprefix = entries[start][0]
    close_re = re.compile(rf"^\s{{0,3}}{re.escape(fence[0])}{{{len(fence)},}}\s*\Z")
    lines = [qprefix + entries[start][1]]
    idx = start + 1
    while idx < len(entries):
        fq, fline = entries[idx]
        lines.append(fq + fline)
        idx += 1
        if fq == qprefix and close_re.match(fline):
            break
    return lines, idx


def _consume_html_comment(
    entries: Sequence[tuple[str, str]], start: int
) -> tuple[list[str], int]:
    """Consumes a multi-line HTML comment verbatim starting at ``start``.

    Args:
        entries: Quote-split ``(qprefix, inner_line)`` entries.
        start: Line index containing the opening ``<!--``.

    Returns:
        Tuple of ``(verbatim_lines, next_index)``.
    """
    lines = [entries[start][0] + entries[start][1]]
    idx = start + 1
    while idx < len(entries):
        hq, hline = entries[idx]
        lines.append(hq + hline)
        idx += 1
        if "-->" in hline:
            break
    return lines, idx


def _consume_table_block(
    entries: Sequence[tuple[str, str]], start: int
) -> tuple[list[str], int]:
    """Consumes a Markdown pipe table verbatim starting at ``start``.

    Args:
        entries: Quote-split ``(qprefix, inner_line)`` entries.
        start: Table header line index.

    Returns:
        Tuple of ``(verbatim_lines, next_index)``.
    """
    qprefix = entries[start][0]
    lines = [
        qprefix + entries[start][1],
        entries[start + 1][0] + entries[start + 1][1],
    ]
    idx = start + 2
    while idx < len(entries) and entries[idx][0] == qprefix:
        if "|" not in entries[idx][1]:
            break
        lines.append(entries[idx][0] + entries[idx][1])
        idx += 1
    return lines, idx


def _wrap_list_item(
    entries: Sequence[tuple[str, str]],
    start: int,
    marker: str,
    item_body: str,
) -> tuple[list[str], bool, int]:
    """Wraps a single list item (bullet, ordered, or task) and its continuation.

    Args:
        entries: Quote-split ``(qprefix, inner_line)`` entries.
        start: Line index of the list marker.
        marker: Indentation plus bullet/checkbox prefix on line 0.
        item_body: Prose text after ``marker`` on line 0.

    Returns:
        Tuple of ``(output_lines, changed, next_index)``.
    """
    qprefix = entries[start][0]
    if not item_body.strip():
        return [qprefix + entries[start][1]], False, start + 1
    end = _consume_prose_run(entries, start, qprefix, allow_indented=True)
    block_entries = [(qprefix, item_body)] + list(entries[start + 1 : end])
    raw_list_lines = [q + ln for q, ln in entries[start:end]]
    wrapped_lines, changed = _wrap_paragraph_block(
        block_entries,
        initial_indent=marker,
        subsequent_indent=" " * len(marker),
        raw_lines=raw_list_lines,
    )
    return wrapped_lines, changed, end


def _non_ws_tokens(text: str) -> list[str]:
    """Extracts non-whitespace tokens after stripping leading quote markers.

    Args:
        text: Markdown body string.

    Returns:
        Ordered list of non-whitespace content tokens.
    """
    tokens: list[str] = []
    for line in text.splitlines():
        stripped = _LEADING_QUOTES_RE.sub("", line)
        tokens.extend(stripped.split())
    return tokens


def verify_token_equivalence(before: str, after: str) -> None:
    """Verifies that ``after`` preserves every non-whitespace token of ``before``.

    Args:
        before: Sanitized Markdown body prior to wrapping.
        after: Wrapped Markdown body produced by ``wrap_markdown_body``.
    """
    before_tokens = _non_ws_tokens(before)
    after_tokens = _non_ws_tokens(after)
    if before_tokens != after_tokens:
        raise WrapPrBodyError(
            "Wrapped PR body failed token-equivalence verification "
            f"(before={len(before_tokens)} tokens, after={len(after_tokens)} tokens)."
        )


def wrap_markdown_body(body: str) -> tuple[str, int]:
    """Deterministically wraps Markdown prose lines to ``_WRAP_WIDTH`` columns.

    Preserves fenced code blocks, HTML comments/blocks, headings, Markdown tables,
    link reference definitions, hard line breaks, URLs, and Markdown links.

    Args:
        body: Raw or sanitized PR description Markdown text.

    Returns:
        Tuple of ``(wrapped_body, wrapped_block_count)``.
    """
    sanitized = sanitize_text(body)
    if not sanitized:
        return sanitized, 0

    had_trailing_newline = sanitized.endswith("\n")
    entries = _split_quote_lines(sanitized.splitlines())
    out: list[str] = []
    wrapped_blocks = 0
    i = 0
    n = len(entries)

    while i < n:
        qprefix, line = entries[i]
        raw = qprefix + line

        fence_match = _FENCE_RE.match(line)
        if fence_match:
            fence = fence_match.group(1) or fence_match.group(2)
            assert fence is not None  # type assert
            block, i = _consume_fenced_block(entries, i, fence)
            out.extend(block)
            continue

        if _HTML_COMMENT_START_RE.match(line) and "-->" not in line:
            block, i = _consume_html_comment(entries, i)
            out.extend(block)
            continue

        if not line.strip():
            out.append(raw)
            i += 1
            continue

        if _is_table_header(entries, i):
            block, i = _consume_table_block(entries, i)
            out.extend(block)
            continue

        if (
            _is_verbatim_single_line(line)
            or line.startswith("    ")
            or line.startswith("\t")
        ):
            out.append(raw)
            i += 1
            continue

        list_match = _LIST_ITEM_RE.match(line)
        if list_match:
            block, changed, i = _wrap_list_item(
                entries, i, list_match.group(1), list_match.group(2)
            )
            out.extend(block)
            if changed:
                wrapped_blocks += 1
            continue

        # Setext headings apply only to non-list paragraphs.
        if (
            i + 1 < n
            and entries[i + 1][0] == qprefix
            and _SETEXT_UNDERLINE_RE.match(entries[i + 1][1])
        ):
            out.append(raw)
            out.append(entries[i + 1][0] + entries[i + 1][1])
            i += 2
            continue

        leading_spaces = len(line) - len(line.lstrip(" "))
        para_indent = " " * leading_spaces if 0 < leading_spaces < 4 else ""
        end = _consume_prose_run(entries, i, qprefix, allow_indented=False)
        raw_para_lines = [q + ln for q, ln in entries[i:end]]
        wrapped_lines, changed = _wrap_paragraph_block(
            entries[i:end],
            initial_indent=para_indent,
            subsequent_indent=para_indent,
            raw_lines=raw_para_lines,
        )
        out.extend(wrapped_lines)
        if changed:
            wrapped_blocks += 1
        i = end

    result = "\n".join(out)
    if had_trailing_newline:
        result += "\n"
    verify_token_equivalence(sanitized, result)
    return result, wrapped_blocks


def _attach_subprocess_notes(
    exc: subprocess.CalledProcessError | subprocess.TimeoutExpired,
) -> None:
    """Attaches sanitized STDOUT and STDERR diagnostics onto ``exc``.

    Args:
        exc: Failed or timed-out ``subprocess.run`` exception.
    """
    for label, stream in (("STDOUT", exc.stdout), ("STDERR", exc.stderr)):
        if isinstance(stream, bytes):
            text = stream.decode("utf-8", errors="replace")
        elif isinstance(stream, str):
            text = stream
        else:
            continue
        cleaned = sanitize_text(text.strip())
        if cleaned:
            exc.add_note(
                f"==================== {label} BEGIN ====================\n"
                f"{cleaned}\n"
                f"==================== {label} END ===================="
            )


def _fetch_pr_body(repo: str, pr_number: int) -> str:
    """Fetches the current PR body text via ``gh pr view``.

    Args:
        repo: Validated ``owner/name`` GitHub repository slug.
        pr_number: Positive pull request number.

    Returns:
        PR body string (empty string when GitHub returns ``null``).
    """
    try:
        result = subprocess.run(
            [
                "gh",
                "pr",
                "view",
                f"--repo={repo}",
                "--json=body",
                "--",
                str(pr_number),
            ],
            capture_output=True,
            text=True,
            timeout=_GH_TIMEOUT_SECONDS,
            check=True,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        _attach_subprocess_notes(exc)
        raise
    payload = json.loads(result.stdout or "{}")
    if not isinstance(payload, dict):
        raise WrapPrBodyError(
            "Unexpected non-object JSON payload in gh pr view response."
        )
    body = payload.get("body")
    if body is None:
        return ""
    if not isinstance(body, str):
        raise WrapPrBodyError("Unexpected non-string PR body in gh response.")
    return body


def _apply_pr_body(repo: str, pr_number: int, body: str) -> None:
    """Applies ``body`` via ``gh pr edit --body-file=-`` on stdin.

    Args:
        repo: Validated ``owner/name`` GitHub repository slug.
        pr_number: Positive pull request number.
        body: Wrapped and token-verified Markdown PR body.
    """
    try:
        subprocess.run(
            [
                "gh",
                "pr",
                "edit",
                f"--repo={repo}",
                "--body-file=-",
                "--",
                str(pr_number),
            ],
            input=body,
            capture_output=True,
            text=True,
            timeout=_GH_TIMEOUT_SECONDS,
            check=True,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        _attach_subprocess_notes(exc)
        raise


class WrapPrBodyError(Exception):
    """Raised when token verification or ``gh`` response validation fails."""


def main(argv: Sequence[str] | None = None) -> int:
    """Fetches, wraps, verifies, and updates a PR body.

    Args:
        argv: Optional CLI argument list; defaults to ``sys.argv[1:]``.

    Returns:
        Process exit status code (``0`` on success).
    """
    parser = build_parser()
    args = parser.parse_args(list(argv) if argv is not None else None)
    repo = validate_repo_slug(args.repo)
    pr_number = validate_pr_number(args.pr_number)

    raw_body = _fetch_pr_body(repo, pr_number)
    sanitized_body = sanitize_text(raw_body)
    wrapped_body, wrapped_blocks = wrap_markdown_body(sanitized_body)

    if wrapped_blocks == 0 or wrapped_body == sanitized_body:
        print(
            json.dumps(
                {
                    "pr": pr_number,
                    "repo": repo,
                    "status": "unchanged",
                    "wrapped_blocks": 0,
                }
            )
        )
        return 0

    if args.dry_run:
        print(
            json.dumps(
                {
                    "pr": pr_number,
                    "repo": repo,
                    "status": "would_update",
                    "wrapped_blocks": wrapped_blocks,
                }
            )
        )
        return 0

    _apply_pr_body(repo, pr_number, wrapped_body)
    print(
        json.dumps(
            {
                "pr": pr_number,
                "repo": repo,
                "status": "updated",
                "wrapped_blocks": wrapped_blocks,
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

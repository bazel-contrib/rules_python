"""Pure-stdlib helpers for sdist_wheel_builder."""

from __future__ import annotations

import re
from pathlib import Path

_BAZEL_LAUNCHER_VARS = (
    "PYTHONSAFEPATH",
    "PYTHONPATH",
    "PYTHONHOME",
    "RUNFILES_DIR",
    "RUNFILES_MANIFEST_FILE",
    "RUNFILES_MANIFEST_ONLY",
)


def scrub_bazel_env(env: dict[str, str]) -> dict[str, str]:
    """Remove Bazel py_binary launcher variables from `env` in-place."""
    for key in _BAZEL_LAUNCHER_VARS:
        env.pop(key, None)
    return env


def sanitize_wheel_entry_path(name: str) -> list[str] | None:
    """Validate and split a wheel zip member path into normalized path components.

    Returns None for directory entries (`name.endswith("/")`).
    Raises ValueError if the path is absolute, contains backslashes, drive
    letters, empty segments, `.`, or `..`.
    """
    if name.endswith("/"):
        return None
    if name.startswith("/") or "\\" in name:
        raise ValueError(f"Unsafe wheel entry path: {name!r}")
    parts = name.split("/")
    if ":" in parts[0]:
        raise ValueError(f"Unsafe wheel entry path: {name!r}")
    for part in parts:
        if part in ("", ".", ".."):
            raise ValueError(f"Unsafe wheel entry path: {name!r}")
    return parts


def single_wheel_in(wheel_dir: Path, *, check_stray: bool = False) -> Path:
    """Return the single `.whl` file inside `wheel_dir`, or raise `ValueError`."""
    entries = sorted(wheel_dir.iterdir())
    whls = [p for p in entries if p.is_file() and p.suffix == ".whl"]
    if len(whls) != 1:
        raise ValueError(
            f"Expected 1 .whl file in '{wheel_dir}', found {len(whls)}: {[p.name for p in whls]}"
        )
    if check_stray and len(entries) != 1:
        stray = [p.name for p in entries if p != whls[0]]
        raise ValueError(f"Unexpected non-wheel files in '{wheel_dir}': {stray}")
    return whls[0]


_HUNK_HEADER_RE = re.compile(rb"^@@ -(\d+)(?:,(\d+))? \+\d+(?:,(\d+))? @@")
_UNSUPPORTED_PATCH_PREFIXES = (
    b"Binary files ",
    b"GIT binary patch",
    b"rename from ",
    b"rename to ",
    b"copy from ",
    b"copy to ",
)


def _strip_patch_path(raw_path: bytes, strip: int) -> str:
    path_bytes = raw_path.split(b"\t", 1)[0].strip()
    try:
        path = path_bytes.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ValueError(f"Non-UTF-8 path in patch header: {raw_path!r}") from exc
    if path == "/dev/null":
        return path
    if path.startswith("/") or "\\" in path or ":" in path.split("/", 1)[0]:
        raise ValueError(f"Unsafe patch path: {path!r}")
    parts = [p for p in path.split("/") if p]
    if strip >= len(parts):
        raise ValueError(f"Cannot strip {strip} components from patch path '{path}'")
    return "/".join(parts[strip:])


def _find_hunk_position(
    file_lines: list[bytes],
    preferred_pos: int,
    old_ops: list[bytes],
    min_pos: int = 0,
) -> int | None:
    def _matches(pos: int) -> bool:
        return (
            min_pos <= pos
            and pos + len(old_ops) <= len(file_lines)
            and all(
                file_lines[pos + idx].rstrip(b"\r\n") == expected
                for idx, expected in enumerate(old_ops)
            )
        )

    if not old_ops:
        return preferred_pos if min_pos <= preferred_pos <= len(file_lines) else None
    if _matches(preferred_pos):
        return preferred_pos
    max_delta = max(preferred_pos - min_pos, len(file_lines) - preferred_pos)
    for delta in range(1, max_delta + 1):
        for candidate in (preferred_pos - delta, preferred_pos + delta):
            if _matches(candidate):
                return candidate
    return None


def _parse_patch_hunk(
    lines: list[bytes],
    i: int,
    patch_path: Path,
    target_rel: str,
) -> tuple[int, int, list[tuple[bytes, bytes, bool]], int]:
    n = len(lines)
    m = _HUNK_HEADER_RE.match(lines[i])
    if not m:
        raise ValueError(f"Invalid hunk header in {patch_path}: {lines[i]!r}")
    old_start = int(m.group(1))
    old_count = int(m.group(2)) if m.group(2) is not None else 1
    new_count = int(m.group(3)) if m.group(3) is not None else 1
    i += 1

    rem_old = old_count
    rem_new = new_count
    hunk_ops: list[tuple[bytes, bytes, bool]] = []

    while rem_old > 0 or rem_new > 0:
        if i >= n:
            raise ValueError(
                f"Unexpected end of patch {patch_path} inside hunk for {target_rel}"
            )
        hline = lines[i]
        i += 1
        if hline in (b"\n", b"\r\n") and rem_old > 0 and rem_new > 0:
            op = b" "
            body = b""
        else:
            op = hline[:1]
            body = hline[1:].rstrip(b"\r\n")

        if op == b" ":
            if rem_old <= 0 or rem_new <= 0:
                raise ValueError(
                    f"Unexpected context line in {patch_path} for {target_rel}"
                )
            rem_old -= 1
            rem_new -= 1
        elif op == b"-":
            if rem_old <= 0:
                raise ValueError(
                    f"Unexpected deletion line in {patch_path} for {target_rel}"
                )
            rem_old -= 1
        elif op == b"+":
            if rem_new <= 0:
                raise ValueError(
                    f"Unexpected addition line in {patch_path} for {target_rel}"
                )
            rem_new -= 1
        else:
            raise ValueError(
                f"Malformed hunk line in {patch_path} for {target_rel}: {hline!r}"
            )

        no_nl = False
        if i < n and lines[i].startswith(b"\\"):
            no_nl = True
            i += 1
        hunk_ops.append((op, body, no_nl))

    return old_start, old_count, hunk_ops, i


def _apply_hunk_ops(
    file_lines: list[bytes],
    match_pos: int,
    hunk_ops: list[tuple[bytes, bytes, bool]],
    eol: bytes,
) -> tuple[list[bytes], int]:
    replacement: list[bytes] = []
    cur_old = match_pos
    for op, body, no_nl in hunk_ops:
        if op == b"-":
            cur_old += 1
            continue
        if op == b"+":
            replacement.append(body if no_nl else (body + eol))
            continue
        orig_line = file_lines[cur_old]
        cur_old += 1
        if no_nl:
            replacement.append(orig_line.rstrip(b"\r\n"))
        elif not orig_line.endswith((b"\n", b"\r\n")):
            replacement.append(orig_line + eol)
        else:
            replacement.append(orig_line)
    return replacement, cur_old


def apply_unified_patch(
    root_dir: Path,
    patch_path: Path,
    strip: int = 0,
) -> set[str]:
    """Apply a unified diff file strictly under `root_dir`, preserving line endings.

    Returns the set of relative POSIX paths under `root_dir` touched by the patch.
    """
    root_resolved = root_dir.resolve()
    lines = patch_path.read_bytes().splitlines(keepends=True)
    i = 0
    n = len(lines)
    applied_any = False
    just_finished_hunk = False
    touched: set[str] = set()

    while i < n:
        line = lines[i]
        if line.startswith(_UNSUPPORTED_PATCH_PREFIXES):
            raise ValueError(
                f"Unsupported binary or rename/copy patch directive in {patch_path}: {line!r}"
            )
        is_file_header = (
            line.startswith(b"--- ") and i + 1 < n and lines[i + 1].startswith(b"+++ ")
        )
        if not is_file_header:
            if _HUNK_HEADER_RE.match(line):
                raise ValueError(
                    f"Hunk without preceding '--- '/'+++ ' file header in {patch_path}: {line!r}"
                )
            if (
                just_finished_hunk
                and line.startswith((b"+", b"-", b" "))
                and not line.startswith(b"+++ ")
                and line not in (b"-- \n", b"-- \r\n")
            ):
                raise ValueError(
                    f"Unexpected diff body line outside hunk in {patch_path}: {line!r}"
                )
            just_finished_hunk = False
            i += 1
            continue
        just_finished_hunk = False

        old_rel = _strip_patch_path(line[4:], strip)
        new_rel = _strip_patch_path(lines[i + 1][4:], strip)
        i += 2

        if (
            strip == 0
            and (old_rel.startswith("a/") or old_rel == "/dev/null")
            and (new_rel.startswith("b/") or new_rel == "/dev/null")
            and (old_rel != "/dev/null" or new_rel != "/dev/null")
        ):
            raise ValueError(
                f"Patch {patch_path}: patch looks git-formatted (a/ b/ prefixes); use strip=1"
            )

        target_rel = old_rel if new_rel == "/dev/null" else new_rel
        target_file = root_dir / target_rel
        target_resolved = target_file.resolve()
        if (
            not target_resolved.is_relative_to(root_resolved)
            or target_resolved == root_resolved
        ):
            raise ValueError(
                f"Patch target '{target_rel}' escapes root directory '{root_dir}'"
            )

        if old_rel == "/dev/null":
            if target_file.exists():
                raise ValueError(
                    f"Patch {patch_path} attempts to create existing file '{target_rel}'"
                )
            file_lines: list[bytes] = []
        elif not target_file.exists():
            raise ValueError(
                f"Patch {patch_path} targets non-existent file '{target_rel}'"
            )
        else:
            file_lines = target_file.read_bytes().splitlines(keepends=True)

        eol = b"\r\n" if any(fl.endswith(b"\r\n") for fl in file_lines) else b"\n"

        offset = 0
        min_pos = 0
        file_had_hunk = False
        while i < n and lines[i].startswith(b"@@ "):
            old_start, old_count, hunk_ops, i = _parse_patch_hunk(
                lines, i, patch_path, target_rel
            )
            old_bodies = [body for op, body, _ in hunk_ops if op in (b" ", b"-")]
            if old_count == 0:
                preferred = max(0, old_start + offset)
            else:
                preferred = 0 if old_start == 0 else max(0, old_start - 1 + offset)
            match_pos = _find_hunk_position(
                file_lines, preferred, old_bodies, min_pos=min_pos
            )
            if match_pos is None:
                raise ValueError(
                    f"Patch {patch_path} failed to apply to {target_rel} at line {old_start}: context mismatch"
                )

            replacement, cur_old = _apply_hunk_ops(file_lines, match_pos, hunk_ops, eol)
            file_lines[match_pos:cur_old] = replacement
            offset += (match_pos - preferred) + len(replacement) - (cur_old - match_pos)
            min_pos = match_pos + len(replacement)
            file_had_hunk = True
            applied_any = True

        just_finished_hunk = True
        if not file_had_hunk:
            raise ValueError(
                f"Patch {patch_path} has file header for {target_rel} without any hunks"
            )

        if new_rel == "/dev/null":
            if file_lines:
                raise ValueError(
                    f"Delete patch {patch_path} for '{target_rel}' did not consume entire file"
                )
            if target_file.exists():
                target_file.unlink()
        else:
            target_file.parent.mkdir(parents=True, exist_ok=True)
            target_file.write_bytes(b"".join(file_lines))
        touched.add(target_rel)

    if not applied_any:
        raise ValueError(f"No valid unified diff hunks found in {patch_path}")

    return touched

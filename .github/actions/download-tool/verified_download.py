#!/usr/bin/env python3
"""Downloads files with retries, mirrors, and SHA-256 checks.

Usage:
  verified_download.py \\
    --urls https://primary.example.com/tool,https://mirror.example.com/tool \\
    --sha256 <hex-digest> \\
    --executable \\
    --output /path/to/tool

Input format for `--urls`:
  Comma- or newline-delimited list of candidate URLs tried in order per attempt.
"""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import io
import stat
import sys
import tarfile
import urllib.request
import zipfile
from collections.abc import Sequence
from pathlib import Path

# Allow up to 120s per HTTP request before treating the connection as stalled.
DEFAULT_TIMEOUT_SECONDS = 120.0
# Retry up to 5 times (2s, 4s, 8s, 16s) to ride out transient 5xx/reset flakes.
DEFAULT_MAX_ATTEMPTS = 5
DEFAULT_INITIAL_DELAY_SECONDS = 2.0

_USER_AGENT = "rules_python-verified-download/1.0"
_EXEC_BITS = stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH


def _parse_args(argv: list[str]) -> argparse.Namespace:
    """Parses CLI flags for single-file verified downloads."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--urls",
        required=True,
        help=(
            "Comma- or newline-delimited list of candidate URLs to download, "
            "tried in order."
        ),
    )
    parser.add_argument(
        "--sha256",
        required=True,
        help="Expected lowercase or uppercase hex SHA-256 digest.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="Destination file path.",
    )
    parser.add_argument(
        "--executable",
        action="store_true",
        help="Set user/group/other executable permission bits (+x) on output.",
    )
    return parser.parse_args(argv)


def parse_url_list(raw_urls: str) -> list[str]:
    """Extracts ordered non-empty URLs from comma- or newline-delimited text."""
    urls: list[str] = []
    for line in raw_urls.splitlines():
        for part in line.split(","):
            url = part.strip()
            if url:
                urls.append(url)
    if not urls:
        raise ValueError("At least one URL must be provided")
    return urls


def sha256_bytes(data: bytes) -> str:
    """Returns the lowercase hex SHA-256 digest of `data`."""
    return hashlib.sha256(data).hexdigest().lower()


def verify_sha256(data: bytes, expected_sha256: str) -> bool:
    """Checks `data` against `expected_sha256`, logging a CI warning on mismatch.

    Args:
        data: Raw payload bytes to hash.
        expected_sha256: Expected hex SHA-256 digest.

    Returns:
        True when the digest matches, False otherwise.
    """
    actual = sha256_bytes(data)
    expected = expected_sha256.lower()
    if actual != expected:
        print(
            f"::warning::SHA-256 mismatch: expected {expected}, got {actual}",
            flush=True,
        )
        return False
    return True


def _set_executable(path: Path) -> None:
    """Sets `+x` permission bits (`0o111`) on `path` while keeping existing bits."""
    path.chmod(path.stat().st_mode | _EXEC_BITS)


def _extract_archive_member(data: bytes, url: str, archive_member: str) -> bytes | None:
    """Extracts `archive_member` from a zip or tar archive payload."""
    if zipfile.is_zipfile(io.BytesIO(data)):
        with zipfile.ZipFile(io.BytesIO(data)) as zf:
            if archive_member not in zf.namelist():
                print(
                    f"::warning::Member {archive_member!r} not found in {url}",
                    flush=True,
                )
                return None
            return zf.read(archive_member)

    with tarfile.open(fileobj=io.BytesIO(data), mode="r:*") as tar:
        member = tar.extractfile(archive_member)
        if member is None:
            print(
                f"::warning::Member {archive_member!r} not found in {url}",
                flush=True,
            )
            return None
        return member.read()


def _read_source_bytes(source: tuple[str, str, str], timeout: float) -> bytes | None:
    """Blocking worker that fetches `url` and extracts `archive_member`."""
    url, _, archive_member = source
    req = urllib.request.Request(url, headers={"User-Agent": _USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        data = response.read()
    if archive_member:
        return _extract_archive_member(data, url, archive_member)
    return data


async def _fetch_source(source: tuple[str, str, str], timeout: float) -> bytes | None:
    """Fetches `source` and extracts its optional archive member.

    Args:
        source: `(url, sha256, archive_member)` tuple.
        timeout: Per-request deadline in seconds.

    Returns:
        Payload bytes on success, or `None` if fetching or extraction fails.
    """
    url = source[0]
    try:
        return await asyncio.wait_for(
            asyncio.to_thread(_read_source_bytes, source, timeout),
            timeout=timeout,
        )
    except Exception as exc:  # Retry transient network, HTTP, and archive errors.
        print(f"::warning::Failed to fetch {url}: {exc}", flush=True)
        return None


async def download_verified_bytes(
    sources: Sequence[tuple[str, str, str]],
    *,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
    max_attempts: int = DEFAULT_MAX_ATTEMPTS,
    initial_delay: float = DEFAULT_INITIAL_DELAY_SECONDS,
) -> bytes:
    """Downloads and SHA-256-verifies bytes with retries.

    Args:
        sources: Ordered `(url, sha256, archive_member)` tuples tried on each
            attempt until one succeeds and matches its SHA-256 digest. Pass `""`
            for `archive_member` when `url` serves the raw file directly.
        timeout: Per-request deadline in seconds.
        max_attempts: Maximum outer retry attempts across `sources`.
        initial_delay: Initial backoff delay in seconds (doubled each retry).

    Returns:
        Verified payload bytes from the first matching source.

    Raises:
        ValueError: If `sources` is empty.
        DownloadError: If all retry attempts fail to produce verified bytes.
    """
    if not sources:
        raise ValueError("sources must not be empty")

    delay = initial_delay
    for attempt in range(1, max_attempts + 1):
        for source in sources:
            _, expected_sha256, _ = source
            data = await _fetch_source(source, timeout)
            if data is not None and verify_sha256(data, expected_sha256):
                return data

        if attempt < max_attempts:
            print(
                f"::warning::Download failed (attempt {attempt}/{max_attempts}); "
                f"retrying in {delay:g}s...",
                flush=True,
            )
            await asyncio.sleep(delay)
            delay *= 2

    raise DownloadError(f"Failed to download after {max_attempts} attempts")


def _reuse_cached_file(dest: Path, expected_shas: set[str], executable: bool) -> bool:
    """Returns True if `dest` exists and matches any digest in `expected_shas`."""
    if not dest.is_file():
        return False
    if sha256_bytes(dest.read_bytes()) not in expected_shas:
        return False
    if executable:
        _set_executable(dest)
    return True


def _write_output_file(dest: Path, data: bytes, executable: bool) -> None:
    """Writes verified `data` to `dest` and optionally marks it executable."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    if executable:
        _set_executable(dest)


async def download_verified_file(
    dest: Path,
    sources: Sequence[tuple[str, str, str]],
    *,
    executable: bool = False,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
    max_attempts: int = DEFAULT_MAX_ATTEMPTS,
    initial_delay: float = DEFAULT_INITIAL_DELAY_SECONDS,
) -> None:
    """Ensures `dest` contains SHA-256-verified bytes.

    Reuses `dest` without network requests if `dest` already exists and its
    SHA-256 matches any entry in `sources`.

    Args:
        dest: Destination file path to verify or write.
        sources: Ordered `(url, sha256, archive_member)` tuples. Pass `""` for
            `archive_member` when `url` serves the raw file directly.
        executable: Whether to mark `dest` executable (`+x`).
        timeout: Per-request deadline in seconds.
        max_attempts: Maximum outer retry attempts across `sources`.
        initial_delay: Initial backoff delay in seconds (doubled each retry).
    """
    expected_shas = {sha256.lower() for _, sha256, _ in sources}
    if await asyncio.to_thread(_reuse_cached_file, dest, expected_shas, executable):
        return

    data = await download_verified_bytes(
        sources,
        timeout=timeout,
        max_attempts=max_attempts,
        initial_delay=initial_delay,
    )
    await asyncio.to_thread(_write_output_file, dest, data, executable)


class DownloadError(Exception):
    """Raised when all candidate sources and retry attempts fail verification."""


async def _async_main(argv: list[str]) -> int:
    """Async CLI entry point."""
    args = _parse_args(argv)
    urls = parse_url_list(args.urls)
    sources = [(url, args.sha256, "") for url in urls]
    await download_verified_file(
        args.output,
        sources,
        executable=args.executable,
    )
    print(f"Downloaded and verified {args.output}")
    return 0


def main(argv: list[str]) -> int:
    """Synchronous CLI entry point."""
    return asyncio.run(_async_main(argv))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

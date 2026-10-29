#!/usr/bin/env python3
"""Downloads Bazelisk and the Bazel binary with retries and mirror fallback.

Why we download Bazelisk here instead of setting `bazelisk-version` on
`bazel-contrib/setup-bazel`:
- `setup-bazel` resolves `bazelisk-version` by querying
  `https://api.github.com/repos/bazelbuild/bazelisk/releases` without retries
  (which intermittently returns HTTP 200 with an empty `[]` body) and downloads
  the binary without retries or SHA-256 verification.
- Storing the downloaded Bazelisk binary in `<bazelisk-cache>/bin` allows
  `setup-bazel`'s `bazelisk-cache: true` to persist Bazelisk across workflow
  runs alongside the downloaded Bazel binary.

Why we also run `bazel --version` with retries:
- Bazelisk retries initial HTTP GET headers (`client.Do`), but does not retry
  mid-stream transfer errors during `io.Copy` (such as HTTP/2 `INTERNAL_ERROR`
  stream resets from `releases.bazel.build`). Running `bazel --version`
  triggers the Bazel download upfront (without starting the Bazel server JVM)
  and retries on transient failures.
"""

from __future__ import annotations

import hashlib
import io
import os
import platform
import shutil
import stat
import subprocess
import sys
import tarfile
import time
import urllib.request
from pathlib import Path

DOWNLOAD_TIMEOUT_SECONDS = 120
MAX_ATTEMPTS = 5
INITIAL_DELAY_SECONDS = 2.0

# Maps "<os>-<arch>" to a list of (url, sha256) tuples tried in order.
# Primary URLs use v1.30.0 (latest GitHub release); the npm mirror fallback uses
# 1.28.1 (latest version published to the npm registry).
# fmt: off
BAZELISK_URLS: dict[str, list[tuple[str, str]]] = {
    "darwin-amd64": [
        ("https://github.com/bazelbuild/bazelisk/releases/download/v1.30.0/bazelisk-darwin-amd64", "a0e6468b0c6b812f782d8cbfb05824121f6980c0bd70aaa1774fb8272bb7b2ad"),
        ("https://registry.npmjs.org/@bazel/bazelisk/-/bazelisk-1.28.1.tgz", "023225736cea5dc88f2b0807d5b1af4eb0f69a4ed45e3994b2c18c263bc80e48"),
    ],
    "darwin-arm64": [
        ("https://github.com/bazelbuild/bazelisk/releases/download/v1.30.0/bazelisk-darwin-arm64", "555d2ff912ccd336d0060bdb5251ef2f62629c6f8fbadb59005a45d5625793ec"),
        ("https://registry.npmjs.org/@bazel/bazelisk/-/bazelisk-1.28.1.tgz", "dea3f3f5de2dbc5e269e0132cdd369d5efe738f7b973d5d4eb2b4f7055a97b39"),
    ],
    "linux-amd64": [
        ("https://github.com/bazelbuild/bazelisk/releases/download/v1.30.0/bazelisk-linux-amd64", "a248ae2b2b62b5baebb748f6fba7203bff1a27e5d01b55399a8406744cb539e8"),
        ("https://registry.npmjs.org/@bazel/bazelisk/-/bazelisk-1.28.1.tgz", "22e7d3a188699982f661cf4687137ee52d1f24fec1ec893d91a6c4d791a75de8"),
    ],
    "linux-arm64": [
        ("https://github.com/bazelbuild/bazelisk/releases/download/v1.30.0/bazelisk-linux-arm64", "b2bcc040c213b44586b121bda6d983c35df121b917c3a7a66fb16f2fa0df1a4f"),
        ("https://registry.npmjs.org/@bazel/bazelisk/-/bazelisk-1.28.1.tgz", "8ded44b58a0d9425a4178af26cf17693feac3b87bdcfef0a2a0898fcd1afc9f2"),
    ],
    "windows-amd64": [
        ("https://github.com/bazelbuild/bazelisk/releases/download/v1.30.0/bazelisk-windows-amd64.exe", "5d14a31e9d8a363c48ba1900dbd56764d730835232eb0d113cce255856ffe3ef"),
        ("https://registry.npmjs.org/@bazel/bazelisk/-/bazelisk-1.28.1.tgz", "b9d65a1f7c2d7af885a96a4fd5aa36b40fb41816d30944390569eef908bdc954"),
    ],
    "windows-arm64": [
        ("https://github.com/bazelbuild/bazelisk/releases/download/v1.30.0/bazelisk-windows-arm64.exe", "cb832b1d157e0dc5f89108da426f9c6fe087f5b15873e072480ec49cc5afe488"),
        ("https://registry.npmjs.org/@bazel/bazelisk/-/bazelisk-1.28.1.tgz", "85ba3d92a8bdcbecc06657b8c0ae30f4307b552d601d9d6246f8a98aec36c346"),
    ],
}
# fmt: on


def _detect_os() -> str:
    raw = platform.system().lower()
    if raw.startswith("linux"):
        return "linux"
    if raw in ("macos", "darwin") or raw.startswith("darwin"):
        return "darwin"
    if raw.startswith(("windows", "mingw", "msys", "cygwin")):
        return "windows"
    raise RuntimeError(f"Unsupported operating system: {raw}")


def _detect_arch() -> str:
    raw = platform.machine().lower()
    if raw in ("x64", "x86_64", "amd64"):
        return "amd64"
    if raw in ("arm64", "aarch64"):
        return "arm64"
    raise RuntimeError(f"Unsupported architecture: {raw}")


def _verify_sha256_bytes(data: bytes, expected: str) -> bool:
    actual = hashlib.sha256(data).hexdigest().lower()
    if actual != expected.lower():
        print(
            f"::warning::SHA-256 mismatch: expected {expected.lower()}, got {actual}",
            flush=True,
        )
        return False
    return True


def _bazelisk_cache_dir(os_name: str) -> Path:
    bazelisk_home = os.environ.get("BAZELISK_HOME")
    if bazelisk_home:
        return Path(bazelisk_home)
    home = Path.home()
    if os_name == "darwin":
        return home / "Library/Caches/bazelisk"
    if os_name == "windows":
        return home / "AppData/Local/bazelisk"
    xdg_cache = os.environ.get("XDG_CACHE_HOME")
    base = Path(xdg_cache) if xdg_cache else (home / ".cache")
    return base / "bazelisk"


def _clean_bazelisk_cache() -> None:
    """Removes partial Bazelisk cache dirs so setup-bazel does not cache them."""
    home = Path.home()
    xdg_cache = os.environ.get("XDG_CACHE_HOME")
    candidates = [
        (Path(xdg_cache) if xdg_cache else (home / ".cache")) / "bazelisk",
        home / "Library/Caches/bazelisk",
        home / "AppData/Local/bazelisk",
    ]
    bazelisk_home = os.environ.get("BAZELISK_HOME")
    if bazelisk_home:
        candidates.append(Path(bazelisk_home))
    for path in candidates:
        shutil.rmtree(path, ignore_errors=True)


def _add_to_path(bin_dir: Path) -> None:
    github_path = os.environ.get("GITHUB_PATH")
    if github_path:
        with Path(github_path).open("a", encoding="utf-8") as f:
            f.write(f"{bin_dir}\n")
    current_path = os.environ.get("PATH", "")
    os.environ["PATH"] = (
        f"{bin_dir}{os.pathsep}{current_path}" if current_path else str(bin_dir)
    )


def _fetch_bazelisk(url: str, os_name: str, arch_name: str, ext: str) -> bytes | None:
    try:
        with urllib.request.urlopen(url, timeout=DOWNLOAD_TIMEOUT_SECONDS) as response:
            data = response.read()
        if url.endswith(".tgz"):
            member_name = f"package/bazelisk-{os_name}_{arch_name}{ext}"
            with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tar:
                member = tar.extractfile(member_name)
                if member is None:
                    return None
                return member.read()
        return data
    except Exception as exc:  # noqa: BLE001
        print(f"::warning::Failed to fetch {url}: {exc}", flush=True)
        return None


def _install_bazelisk_binary(
    data: bytes, bin_dir: Path, bazel_bin: Path, bazelisk_bin: Path
) -> None:
    bin_dir.mkdir(parents=True, exist_ok=True)
    bazel_bin.write_bytes(data)
    exec_bits = stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH
    bazel_bin.chmod(bazel_bin.stat().st_mode | exec_bits)
    shutil.copy2(bazel_bin, bazelisk_bin)
    bazelisk_bin.chmod(bazelisk_bin.stat().st_mode | exec_bits)
    _add_to_path(bin_dir)


def _setup_bazelisk(
    max_attempts: int = MAX_ATTEMPTS,
    initial_delay: float = INITIAL_DELAY_SECONDS,
) -> None:
    os_name = _detect_os()
    arch_name = _detect_arch()
    ext = ".exe" if os_name == "windows" else ""
    key = f"{os_name}-{arch_name}"
    if key not in BAZELISK_URLS:
        raise RuntimeError(f"No Bazelisk URLs configured for {key}")
    sources = BAZELISK_URLS[key]
    cache_dir = _bazelisk_cache_dir(os_name)
    bin_dir = cache_dir / "bin"
    bazel_bin = bin_dir / f"bazel{ext}"
    bazelisk_bin = bin_dir / f"bazelisk{ext}"

    if bazel_bin.is_file():
        actual_sha = hashlib.sha256(bazel_bin.read_bytes()).hexdigest().lower()
        if any(actual_sha == sha256.lower() for _, sha256 in sources):
            exec_bits = stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH
            bazel_bin.chmod(bazel_bin.stat().st_mode | exec_bits)
            if not bazelisk_bin.is_file():
                shutil.copy2(bazel_bin, bazelisk_bin)
                bazelisk_bin.chmod(bazelisk_bin.stat().st_mode | exec_bits)
            _add_to_path(bin_dir)
            return

    delay = initial_delay
    for attempt in range(1, max_attempts + 1):
        for url, expected_sha in sources:
            data = _fetch_bazelisk(url, os_name, arch_name, ext)
            if data is not None and _verify_sha256_bytes(data, expected_sha):
                _install_bazelisk_binary(data, bin_dir, bazel_bin, bazelisk_bin)
                return

        if attempt < max_attempts:
            print(
                f"::warning::Failed to download Bazelisk (attempt {attempt}/{max_attempts}); retrying in {delay:g}s...",
                flush=True,
            )
            time.sleep(delay)
            delay *= 2

    print(
        f"::error::Failed to download Bazelisk after {max_attempts} attempts",
        flush=True,
    )
    _clean_bazelisk_cache()
    sys.exit(1)


def _run_bazel_version() -> bool:
    bazel_exe = shutil.which("bazel", path=os.environ.get("PATH")) or "bazel"
    result = subprocess.run([bazel_exe, "--version"], check=False)
    return result.returncode == 0


def _download_bazel(
    max_attempts: int = MAX_ATTEMPTS,
    initial_delay: float = INITIAL_DELAY_SECONDS,
) -> None:
    delay = initial_delay
    for attempt in range(1, max_attempts + 1):
        if _run_bazel_version():
            return

        if attempt < max_attempts:
            print(
                f"::warning::Failed to download Bazel (attempt {attempt}/{max_attempts}); retrying in {delay:g}s...",
                flush=True,
            )
            time.sleep(delay)
            delay *= 2

    print(
        f"::error::Failed to download Bazel after {max_attempts} attempts",
        flush=True,
    )
    _clean_bazelisk_cache()
    sys.exit(1)


def main() -> None:
    _setup_bazelisk()
    _download_bazel()


if __name__ == "__main__":
    main()

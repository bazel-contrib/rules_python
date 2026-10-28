#!/usr/bin/env python3
"""Generates an artifacts_manifest.bzl file for built release artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path
from typing import TypedDict


class ArtifactEntry(TypedDict):
    exec_compatible_with: list[str]
    name: str
    sha256: str
    urls: list[str]


_CPU_TO_CONSTRAINT = {
    "aarch64": "@platforms//cpu:aarch64",
    "armv7": "@platforms//cpu:armv7",
    "i686": "@platforms//cpu:x86_32",
    "powerpc64le": "@platforms//cpu:ppc64le",
    "riscv64gc": "@platforms//cpu:riscv64",
    "x86_64": "@platforms//cpu:x86_64",
}

_FILENAME_RE = re.compile(r"^(.+)-((?:" + "|".join(_CPU_TO_CONSTRAINT) + r")-.+)$")


def _cpu_constraint(triple: str) -> str:
    cpu = triple.split("-", 1)[0]
    if cpu in _CPU_TO_CONSTRAINT:
        return _CPU_TO_CONSTRAINT[cpu]
    raise ValueError(f"Unsupported CPU in triple: {triple}")


def _os_constraint(triple: str) -> str:
    if triple.endswith("-apple-darwin"):
        return "@platforms//os:macos"
    if "-pc-windows-" in triple:
        return "@platforms//os:windows"
    if "-linux-" in triple:
        return "@platforms//os:linux"
    raise ValueError(f"Unsupported OS in triple: {triple}")


def generate_manifest(
    tag: str,
    artifacts_dir: Path,
    repo: str,
) -> dict[str, dict[str, list[ArtifactEntry]]]:
    artifacts: dict[str, list[ArtifactEntry]] = {}
    for file_path in sorted(artifacts_dir.iterdir()):
        filename = file_path.name
        base = filename.removesuffix(".exe")
        match = _FILENAME_RE.match(base)
        if not match:
            raise ValueError(
                f"Cannot parse artifact and triple from filename: {filename}"
            )
        artifact, triple = match.group(1), match.group(2)

        cpu = _cpu_constraint(triple)
        os_constraint = _os_constraint(triple)
        name = base.replace("-", "_").replace(".", "_")
        sha256 = hashlib.sha256(file_path.read_bytes()).hexdigest()
        url = f"https://github.com/{repo}/releases/download/{tag}/{filename}"

        artifacts.setdefault(artifact, []).append(
            {
                "exec_compatible_with": [cpu, os_constraint],
                "name": name,
                "sha256": sha256,
                "urls": [url],
            }
        )

    for entries in artifacts.values():
        entries.sort(key=lambda entry: entry["name"])

    return {"artifacts": dict(sorted(artifacts.items()))}


def render_bzl(manifest: dict[str, dict[str, list[ArtifactEntry]]]) -> str:
    manifest_json = json.dumps(manifest, indent=1, sort_keys=True)
    # Embedded in a Starlark string literal, so it must not end the literal
    # early or rely on escape sequences.
    if '"""' in manifest_json or "\\" in manifest_json:
        raise ValueError("Manifest JSON cannot be embedded in a .bzl string")
    return (
        '"""Manifest of prebuilt tool binaries for this release."""\n'
        "\n"
        f'ARTIFACTS_MANIFEST_JSON = """\n{manifest_json}\n"""\n'
    )


def _main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag", help="Release tag name (e.g. 2.4.0).")
    parser.add_argument(
        "artifacts_dir",
        type=Path,
        help="Directory containing built <artifact>-<triple>[.exe] files.",
    )
    parser.add_argument(
        "output_file",
        type=Path,
        help="Path to the artifacts_manifest.bzl file to write.",
    )
    parser.add_argument(
        "repo",
        nargs="?",
        default=os.environ.get("GITHUB_REPOSITORY") or "bazel-contrib/rules_python",
        help="GitHub owner/repository name.",
    )
    args = parser.parse_args(argv)
    try:
        manifest = generate_manifest(args.tag, args.artifacts_dir, args.repo)
        manifest_bzl = render_bzl(manifest)
    except ValueError as err:
        print(f"::error::{err}")
        return 1
    args.output_file.parent.mkdir(parents=True, exist_ok=True)
    args.output_file.write_text(manifest_bzl, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(_main())

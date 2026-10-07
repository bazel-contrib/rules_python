"""Cache identities follow runtime contents and bootstrap configuration."""

import os

import pytest

from tools.zipapp import zip_main_maker


@pytest.fixture(name="generate")
def fixture_generate(tmp_path, monkeypatch):
    template = tmp_path / "template"
    template.write_text("%APP_HASH%\n%OPTIONS%\n")
    payload = tmp_path / "payload"
    payload.write_text("application")
    symlink = tmp_path / "symlink"
    symlink.symlink_to(payload)
    manifest = tmp_path / "manifest"
    manifest.write_text(
        f"rf-file|0|app|{payload}\nrf-symlink|1|link|{symlink}\nrf-empty|empty\n"
    )
    output = tmp_path / "output"

    def generate(options="-Xoriginal"):
        monkeypatch.setattr(
            "sys.argv",
            [
                "zip_main_maker",
                "--template",
                str(template),
                "--output",
                str(output),
                "--substitution",
                "%OPTIONS%=" + options,
                "--hash_files_manifest",
                str(manifest),
            ],
        )
        zip_main_maker.main()
        digest, actual = output.read_text().splitlines()[:2]
        assert len(digest) == 64
        assert actual == options
        return digest

    return generate, template, payload, symlink, manifest


def test_hash_is_stable_across_runs_and_manifest_order(generate):
    run, _, _, _, manifest = generate
    first = run()
    assert run() == first
    manifest.write_text("\n".join(reversed(manifest.read_text().splitlines())) + "\n")
    assert run() == first


@pytest.mark.parametrize(
    "changed", ["content", "link", "layout", "template", "options", "mode"]
)
def test_hash_invalidates_every_runtime_input(generate, changed):
    run, template, payload, symlink, manifest = generate
    original = run()
    if changed == "content":
        payload.write_text("changed application")
    elif changed == "link":
        symlink.unlink()
        symlink.symlink_to(payload.parent / "different")
    elif changed == "layout":
        manifest.write_text(manifest.read_text() + "rf-empty|new/path\n")
    elif changed == "template":
        template.write_text(template.read_text() + "new lifecycle code\n")
    elif changed == "mode":
        if os.name == "nt":
            pytest.skip("Windows chmod does not expose executable mode bits")
        payload.chmod(payload.stat().st_mode ^ 0o100)
    assert run("-Xchanged" if changed == "options" else "-Xoriginal") != original

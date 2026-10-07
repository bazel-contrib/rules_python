"""Entry templates preserve their interpreter and expansion contracts."""

import json
import os
import subprocess
import sys
import textwrap
import zipfile
from pathlib import Path

import pytest

from python.runfiles import runfiles


def test_zip_template_accepts_python39_loader_protocol(tmp_path):
    template = runfiles.CreateOrRaise().Rlocation(os.environ["ZIP_TEMPLATE"])
    assert template is not None
    contents = (
        Path(template)
        .read_text()
        .replace("%archive_metadata%", repr('{"version": 1}'))
        .replace("%bootstrap_parent%", repr("private"))
    )
    archive_path = tmp_path / "application.zip"
    package = "runfiles/private/_rules_python_bootstrap/"
    with zipfile.ZipFile(archive_path, "w") as archive:
        archive.writestr("__main__.py", contents)
        archive.writestr(package + "__init__.py", "from . import entry\n")
        archive.writestr(
            package + "entry.py",
            "import json\n"
            "def archive_main(archive, metadata, arguments):\n"
            "    print(json.dumps([__package__, archive, metadata, arguments]))\n"
            "    return 23\n",
        )
    # Retain the real archive spec and code, but expose only the loader protocol
    # available before zipimporter gained exec_module in Python 3.10.
    driver = textwrap.dedent("""
        import importlib.machinery
        import runpy
        import sys
        import types

        find_spec = importlib.machinery.PathFinder.find_spec
        def find_legacy_spec(name, path=None, target=None):
            spec = find_spec(name, path, target)
            if name == "_rules_python_bootstrap":
                spec.loader = types.SimpleNamespace(get_code=spec.loader.get_code)
            return spec
        importlib.machinery.PathFinder.find_spec = find_legacy_spec
        sys.argv = sys.argv[1:]
        runpy.run_path(sys.argv[0], run_name="__main__")
    """)
    result = subprocess.run(
        [sys.executable, "-c", driver, str(archive_path), "a b", ""],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 23, result.stderr
    assert json.loads(result.stdout) == [
        "_rules_python_bootstrap",
        str(archive_path),
        {"version": 1},
        ["a b", ""],
    ]


def test_custom_directory_template_preserves_bytes():
    path = runfiles.CreateOrRaise().Rlocation(os.environ["CUSTOM_BOOTSTRAP"])
    assert path is not None
    contents = Path(path).read_bytes()
    workspace = os.environ["TEST_WORKSPACE"]
    assert contents.startswith(
        f"custom\r\nworkspace={workspace}\r\nmain={workspace}/".encode()
    )
    assert contents.endswith(b"_custom_application_stage2_bootstrap.py")
    assert b"_rules_python_bootstrap" not in contents


def test_public_provider_keeps_independently_supplied_executable():
    path = runfiles.CreateOrRaise().Rlocation(os.environ["PUBLIC_ZIP"])
    assert path is not None
    with zipfile.ZipFile(path) as archive:
        contents = archive.read(
            f"runfiles/{os.environ['TEST_WORKSPACE']}/"
            "tests/bootstrap_impls/supplied_venv.txt"
        )
    assert contents == b"custom executable supplied without interpreter runfiles"


def test_custom_zip_template_preserves_public_substitutions():
    path = runfiles.CreateOrRaise().Rlocation(os.environ["CUSTOM_ZIP"])
    assert path is not None
    with zipfile.ZipFile(path) as archive:
        contents = archive.read("__main__.py")
    workspace = os.environ["TEST_WORKSPACE"]
    assert contents.startswith(
        f"custom zip\r\nworkspace={workspace}\r\nmain={workspace}/".encode()
    )
    assert contents.endswith(b"_custom_application_stage2_bootstrap.py")
    assert b"_rules_python_bootstrap" not in contents


@pytest.mark.parametrize("status", [0, 23])
@pytest.mark.skipif(os.name == "nt", reason="The raw template uses Bash")
def test_raw_shell_template_accepts_historical_substitutions(tmp_path, status):
    template = runfiles.CreateOrRaise().Rlocation(os.environ["RAW_SHELL_TEMPLATE"])
    assert template is not None
    root = tmp_path / "runfiles"
    venv = root / "app.venv"
    (venv / "bin").mkdir(parents=True)
    (venv / "lib/site-packages").mkdir(parents=True)
    (venv / "pyvenv.cfg").touch()
    (root / "entry.py").write_text(
        "import json, os, sys\n"
        "print(json.dumps([sys.executable, sys.argv[1:], sys._xoptions, "
        "os.environ.get('RULES_PYTHON_ADDITIONAL_INTERPRETER_ARGS')]))\n"
        "sys.exit(int(sys.argv[1]))\n"
    )
    substitutions = {
        "%stage2_bootstrap%": "entry.py",
        "%python_binary%": "app.venv/bin/python3",
        "%python_binary_actual%": Path(sys.executable).resolve().as_posix(),
        "%is_zipfile%": "0",
        "%recreate_venv_at_runtime%": "1",
        "%resolve_python_binary_at_runtime%": "0",
        "%venv_rel_site_packages%": "lib/site-packages",
        "%interpreter_args%": "'-Xscope=target' '-Xtarget_only=present'",
    }
    contents = Path(template).read_text()
    for key, value in substitutions.items():
        contents = contents.replace(key, value)
    launcher = tmp_path / "launcher"
    launcher.write_text(contents)
    temporary = tmp_path / "temporary"
    temporary.mkdir()
    env = dict(os.environ)
    for key in (
        "RULES_PYTHON_EXTRACT_ROOT",
        "RULES_PYTHON_BOOTSTRAP_VERBOSE",
        "PYTHONHOME",
        "PYTHONPATH",
        "PYTHONEXECUTABLE",
        "__PYVENV_LAUNCHER__",
    ):
        env.pop(key, None)
    env.update(
        RUNFILES_DIR=str(root),
        TMPDIR=str(temporary),
        RULES_PYTHON_ADDITIONAL_INTERPRETER_ARGS=(
            "-Xscope=environment -Xenv_only=present"
        ),
    )
    # The historical macOS mktemp ignores TMPDIR without a template. Keep this
    # fixture's allocations inside the test directory without changing the stub.
    wrapper = (
        'mktemp() { command mktemp -d "$TMPDIR/raw.XXXXXXXXXX"; }; '
        'export -f mktemp; exec bash "$@"'
    )
    result = subprocess.run(
        ["bash", "-c", wrapper, "raw-expander", str(launcher), str(status), "a b", ""],
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == status, result.stderr
    executable, args, options, additional = json.loads(result.stdout)
    assert args == [str(status), "a b", ""]
    assert options["scope"] == "target"
    assert options["target_only"] == "present"
    assert options["env_only"] == "present"
    assert additional is None
    assert Path(executable).is_relative_to(temporary)
    assert not Path(executable).exists()
    assert list(temporary.iterdir()) == []

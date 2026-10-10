"""Tests both bootstraps with Bazel 7's native template substitutions.

Render only the placeholders understood by native rules, leaving stage-2 and
venv placeholders untouched. This tests the fallback without requiring native
Python rules, which are unavailable in newer Bazel versions.
"""

from __future__ import annotations

import json
import os
import pathlib
import posixpath
import subprocess
import sys
import tempfile
import unittest

from python.runfiles import runfiles


class NativeBootstrapTest(unittest.TestCase):
    def setUp(self):
        self.script_bootstrap = os.environ.get("BOOTSTRAP") == "script"
        prefix = "native_bootstrap_" if self.script_bootstrap else "native bootstrap "
        self.temp_dir = tempfile.TemporaryDirectory(prefix=prefix)
        self.addCleanup(self.temp_dir.cleanup)
        filename = "launcher.sh" if self.script_bootstrap else "launcher.py"
        self.launcher = pathlib.Path(self.temp_dir.name) / filename
        # The Windows bootstrap looks beside the launcher for .exe.runfiles.
        runfiles_suffix = ".exe.runfiles" if os.name == "nt" else ".runfiles"
        self.runfiles_root = pathlib.Path(str(self.launcher) + runfiles_suffix)
        self.runfiles_root.mkdir()
        template_name = (
            "stage1_bootstrap_template.sh"
            if self.script_bootstrap
            else "python_bootstrap_template.txt"
        )
        self.template = (
            runfiles.CreateOrRaise().root()
            / f"rules_python/python/private/{template_name}"
        ).read_text(encoding="utf-8")

    def _write_runfile(self, path: str, contents: str) -> None:
        file = self.runfiles_root / posixpath.normpath(path)
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(contents, encoding="utf-8")

    def _render(self, substitutions: dict[str, str] | None = None) -> None:
        # This is the native Bazel 7 substitution contract, not a patched
        # launcher. Unrecognized placeholders must remain in the template.
        native_substitutions = {
            "%shebang%": "#!/usr/bin/env python3",
            "%main%": "_main/tool/main.py",
            "%python_binary%": sys.executable.replace("\\", "/"),
            "%imports%": "_main/lib",
            "%import_all%": "False",
            "%is_zipfile%": "False",
            "%workspace_name%": "_main",
        }
        native_substitutions.update(substitutions or {})
        source = self.template
        for placeholder, replacement in native_substitutions.items():
            source = source.replace(placeholder, replacement)
        self.launcher.write_text(source, encoding="utf-8")

    def _run(
        self,
        substitutions: dict[str, str] | None = None,
        extra_env: dict[str, str] | None = None,
        *,
        load_only: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        self._render(substitutions)
        env = dict(os.environ)
        for key in (
            "RUNFILES_DIR",
            "RUNFILES_MANIFEST_FILE",
            "PYTHONPATH",
            "PYTHONSAFEPATH",
        ):
            env.pop(key, None)
        env.update(extra_env or {})
        if load_only:
            command = [
                sys.executable,
                "-c",
                "import json, runpy, sys; "
                "print(json.dumps(runpy.run_path(sys.argv[1])['RUNTIME_VENV_SYMLINKS']))",
                str(self.launcher),
            ]
        elif self.script_bootstrap:
            command = ["bash", str(self.launcher)]
        else:
            command = [sys.executable, str(self.launcher)]
        return subprocess.run(
            command, env=env, capture_output=True, text=True, timeout=30, check=False
        )

    def _assert_success(
        self, result: subprocess.CompletedProcess[str], output: str
    ) -> None:
        self.assertEqual(
            result.returncode,
            0,
            "==================== STDOUT BEGIN ====================\n"
            + result.stdout
            + "==================== STDOUT END ====================\n"
            + "==================== STDERR BEGIN ====================\n"
            + result.stderr
            + "==================== STDERR END ====================",
        )
        self.assertEqual(result.stdout.strip(), output)

    def test_native_main_with_unexpanded_placeholders(self):
        self._write_runfile("_main/tool/main.py", 'print("reached main")\n')
        self._assert_success(self._run(), "reached main")

    def test_declared_import_roots_preserve_order(self):
        self._write_runfile(
            "_main/tool/main.py",
            "from native_declared_fixture import MESSAGE\nprint(MESSAGE)\n",
        )
        self._write_runfile(
            "_main/lib/native_declared_fixture.py", 'MESSAGE = "first"\n'
        )
        self._write_runfile(
            "_main/second/native_declared_fixture.py", 'MESSAGE = "second"\n'
        )
        result = self._run({"%imports%": "_main/lib:_main/second:_main/lib"})
        self._assert_success(result, "first")

    def test_workspace_root_import(self):
        self._write_runfile(
            "_main/tool/main.py",
            "from native_workspace_fixture import MESSAGE\nprint(MESSAGE)\n",
        )
        self._write_runfile(
            "_main/native_workspace_fixture.py", 'MESSAGE = "workspace"\n'
        )
        self._assert_success(self._run({"%imports%": ""}), "workspace")

    def test_external_main_with_import_all(self):
        self._write_runfile(
            "external_repo/tool/main.py",
            "from native_external_fixture import MESSAGE\nprint(MESSAGE)\n",
        )
        self._write_runfile(
            "external_repo/native_external_fixture.py", 'MESSAGE = "external"\n'
        )
        result = self._run(
            {
                "%main%": "_main/../external_repo/tool/main.py",
                "%imports%": "",
                "%import_all%": "True",
            }
        )
        self._assert_success(result, "external")

    def test_import_all_false_does_not_add_other_repositories(self):
        self._write_runfile(
            "_main/tool/main.py",
            "import importlib.util\n"
            "assert importlib.util.find_spec('native_other_fixture') is None\n"
            "print('not imported')\n",
        )
        self._write_runfile("other_repo/native_other_fixture.py", 'MESSAGE = "other"\n')
        self._assert_success(self._run({"%imports%": ""}), "not imported")

    def test_existing_pythonpath_is_preserved_after_declared_imports(self):
        self._write_runfile(
            "_main/tool/main.py",
            "from native_declared_fixture import MESSAGE\n"
            "from native_environment_fixture import EXTRA\n"
            "print(MESSAGE + EXTRA)\n",
        )
        self._write_runfile(
            "_main/lib/native_declared_fixture.py", 'MESSAGE = "declared"\n'
        )
        inherited = pathlib.Path(self.temp_dir.name) / "inherited"
        inherited.mkdir()
        (inherited / "native_declared_fixture.py").write_text('MESSAGE = "inherited"\n')
        (inherited / "native_environment_fixture.py").write_text(
            'EXTRA = "+environment"\n'
        )
        result = self._run(extra_env={"PYTHONPATH": str(inherited)})
        self._assert_success(result, "declared+environment")

    def test_stage2_does_not_export_native_import_roots(self):
        self._write_runfile(
            "_main/stage2.py", "import os\nprint(os.environ.get('PYTHONPATH'))\n"
        )
        result = self._run(
            {
                "%stage2_bootstrap%": "_main/stage2.py",
                "%runtime_venv_symlinks%": "",
                "%interpreter_args%": "",
            },
            extra_env={"PYTHONPATH": "inherited-path"},
        )
        self._assert_success(result, "inherited-path")

    def test_stage2_preserves_substituted_interpreter_args(self):
        self._write_runfile(
            "_main/stage2.py", "import sys\nprint(sys._xoptions['BOOTSTRAP_TEST'])\n"
        )
        result = self._run(
            {
                "%stage2_bootstrap%": "_main/stage2.py",
                "%runtime_venv_symlinks%": "",
                "%interpreter_args%": "-XBOOTSTRAP_TEST=preserved",
            }
        )
        self._assert_success(result, "preserved")

    def test_missing_stage2_and_main_report_error(self):
        result = self._run({"%main%": ""})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("was not substituted", result.stderr)

    @unittest.skipIf(os.environ.get("BOOTSTRAP") == "script", "Python-only venv parser")
    def test_substituted_venv_symlinks_are_preserved(self):
        result = self._run(
            {
                "%stage2_bootstrap%": "_main/stage2.py",
                "%runtime_venv_symlinks%": "lib/site-packages|_main/lib\nbin/helper|tools/helper",
            },
            load_only=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            json.loads(result.stdout),
            {
                os.path.join("lib", "site-packages"): os.path.join("_main", "lib"),
                os.path.join("bin", "helper"): os.path.join("tools", "helper"),
            },
        )

    @unittest.skipIf(os.environ.get("BOOTSTRAP") == "script", "Python-only venv parser")
    def test_malformed_substituted_symlinks_still_fail(self):
        result = self._run({"%runtime_venv_symlinks%": "malformed"}, load_only=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ValueError", result.stderr)


if __name__ == "__main__":
    unittest.main()

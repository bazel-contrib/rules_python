"""Unit tests for wheel_layout, inspect_whl, and action_whl_installer."""

from __future__ import annotations

import contextlib
import importlib.machinery
import importlib.util
import io
import json
import pathlib
import sys
import tempfile
import unittest
import zipfile

import action_whl_installer
import inspect_whl
import wheel_layout


def _write_zip(path: pathlib.Path, entries: dict[str, bytes | str]) -> pathlib.Path:
    with zipfile.ZipFile(path, "w") as zf:
        for name, data in entries.items():
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.external_attr = 0o644 << 16
            raw = data.encode("utf-8") if isinstance(data, str) else data
            zf.writestr(info, raw)
    return path


class WheelLayoutAndInstallerTest(unittest.TestCase):
    def test_sanitize_wheel_entry_path_rejects_traversal(self):
        for bad in [
            "/abs/path.py",
            "\\backslash.py",
            "a\\b.py",
            "../escape.py",
            "pkg/../../escape.py",
            "pkg/./mod.py",
            "pkg//mod.py",
            "C:drive.py",
            "C:/drive.py",
        ]:
            with self.subTest(bad=bad):
                with self.assertRaises(ValueError):
                    wheel_layout.sanitize_wheel_entry_path(bad)

        self.assertEqual(
            wheel_layout.sanitize_wheel_entry_path("pkg/sub/mod.py"),
            ["pkg", "sub", "mod.py"],
        )

    def test_glob_matching(self):
        patterns = [
            wheel_layout.glob_to_regex(p) for p in ["**/*.pyc", "pkg/skip_*.py"]
        ]
        self.assertTrue(wheel_layout.is_excluded("a/b/c.pyc", patterns))
        self.assertTrue(wheel_layout.is_excluded("c.pyc", patterns))
        self.assertTrue(wheel_layout.is_excluded("pkg/skip_me.py", patterns))
        self.assertFalse(wheel_layout.is_excluded("pkg/keep.py", patterns))

    def test_data_dir_stem_and_root_data_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            whl = _write_zip(
                pathlib.Path(tmp) / "mylib-1.0-py3-none-any.whl",
                {
                    "mylib-1.0.dist-info/METADATA": "Name: mylib\nVersion: 1.0\n",
                    "mylib-1.0.dist-info/WHEEL": "Wheel-Version: 1.0\n",
                    "mylib-1.0.dist-info/RECORD": "",
                    "mylib.data": "top-level file ending in .data",
                    "other.data/foo.txt": "not the wheel data dir",
                    "mylib-1.0.data/purelib/mylib/pure.py": "PURE = 1\n",
                    "mylib-1.0.data/platlib/mylib/plat.py": "PLAT = 1\n",
                    "mylib-1.0.data/headers/mylib.h": "#pragma once\n",
                    "mylib-1.0.data/data/etc/cfg.ini": "[cfg]\n",
                    "mylib-1.0.data/scripts/my_tool": "#!python -u\nprint('hi')\n",
                    "mylib-1.0.data/scripts/plain_sh": "#!/bin/sh\necho hi\n",
                },
            )
            info = inspect_whl.inspect_wheel(
                whl,
                srcs_exclude_globs=[],
                data_exclude_globs=[],
            )
            self.assertFalse(info["has_entry_points_txt"])
            self.assertEqual(info["entry_points_content"], "")
            self.assertIn("site-packages/mylib.data", info["extracted_files"])
            self.assertIn("site-packages/other.data/foo.txt", info["extracted_files"])
            self.assertIn("site-packages/mylib/pure.py", info["extracted_files"])
            self.assertIn("site-packages/mylib/plat.py", info["extracted_files"])
            self.assertIn("include/mylib.h", info["extracted_files"])
            self.assertIn("data/etc/cfg.ini", info["extracted_files"])
            self.assertIn("bin/plain_sh", info["extracted_files"])
            self.assertEqual(info["shebang_scripts"], ["my_tool"])

            # Verify parity with action_whl_installer on both unix and windows.
            for target_os in ("unix", "windows"):
                dest = pathlib.Path(tmp) / f"installed_{target_os}"
                action_whl_installer.install_wheel(
                    wheel_path=whl,
                    dest_dir=dest,
                    srcs_exclude_globs=[],
                    data_exclude_globs=[],
                    create_namespace_inits_flag=False,
                    target_os=target_os,
                )
                actual_files = sorted(
                    p.relative_to(dest).as_posix()
                    for p in dest.rglob("*")
                    if p.is_file()
                )
                expected_files = list(info["extracted_files"])
                for s in info["shebang_scripts"]:
                    if target_os == "windows":
                        expected_files.append(f"bin/{s}.bat")
                    else:
                        expected_files.append(f"bin/{s}")
                expected_files.sort()
                self.assertEqual(actual_files, expected_files)
                if target_os == "unix":
                    script_text = (dest / "bin/my_tool").read_text(encoding="utf-8")
                    self.assertTrue(
                        script_text.startswith("#!/bin/sh\n"),
                        script_text,
                    )
                else:
                    self.assertTrue((dest / "bin/my_tool.bat").is_file())

    def test_dist_info_validation_and_entry_points_matching(self):
        with tempfile.TemporaryDirectory() as tmp:
            no_meta = _write_zip(
                pathlib.Path(tmp) / "nometa-1.0-py3-none-any.whl",
                {"nometa/__init__.py": ""},
            )
            with self.assertRaisesRegex(ValueError, "no '\\*\\.dist-info/METADATA'"):
                inspect_whl.inspect_wheel(no_meta)

            multi_meta = _write_zip(
                pathlib.Path(tmp) / "multi-1.0-py3-none-any.whl",
                {
                    "a-1.0.dist-info/METADATA": "Name: a\nVersion: 1.0\n",
                    "b-1.0.dist-info/METADATA": "Name: b\nVersion: 1.0\n",
                },
            )
            with self.assertRaisesRegex(
                ValueError, "multiple \\.dist-info directories"
            ):
                inspect_whl.inspect_wheel(multi_meta)

            stray_ep = _write_zip(
                pathlib.Path(tmp) / "stray-1.0-py3-none-any.whl",
                {
                    "other-2.0.dist-info/entry_points.txt": (
                        "[console_scripts]\nbogus = other:main\n"
                    ),
                    "stray-1.0.dist-info/METADATA": "Name: stray\nVersion: 1.0\n",
                },
            )
            stray_info = inspect_whl.inspect_wheel(stray_ep)
            self.assertFalse(stray_info["has_entry_points_txt"])
            self.assertEqual(stray_info["entry_points_content"], "")

            with_ep = _write_zip(
                pathlib.Path(tmp) / "ep-1.0-py3-none-any.whl",
                {
                    "ep-1.0.dist-info/METADATA": "Name: ep\nVersion: 1.0\n",
                    "ep-1.0.dist-info/entry_points.txt": (
                        "[console_scripts]\nmy-ep = ep:main\n"
                    ),
                },
            )
            ep_info = inspect_whl.inspect_wheel(with_ep)
            self.assertTrue(ep_info["has_entry_points_txt"])
            self.assertIn("my-ep = ep:main", ep_info["entry_points_content"])

    def test_duplicate_destination_and_unknown_data_category_fail(self):
        with tempfile.TemporaryDirectory() as tmp:
            whl = _write_zip(
                pathlib.Path(tmp) / "dup-1.0-py3-none-any.whl",
                {
                    "dup-1.0.dist-info/METADATA": "Name: dup\nVersion: 1.0\n",
                    "dup-1.0.data/purelib/dup/mod.py": "X = 1\n",
                    "dup-1.0.data/platlib/dup/mod.py": "X = 2\n",
                },
            )
            with self.assertRaisesRegex(ValueError, "Detected collision"):
                inspect_whl.inspect_wheel(
                    whl, srcs_exclude_globs=[], data_exclude_globs=[]
                )
            with self.assertRaisesRegex(ValueError, "Detected collision"):
                action_whl_installer.install_wheel(
                    wheel_path=whl,
                    dest_dir=pathlib.Path(tmp) / "out",
                    srcs_exclude_globs=[],
                    data_exclude_globs=[],
                    create_namespace_inits_flag=False,
                    target_os="unix",
                )

            case_whl = _write_zip(
                pathlib.Path(tmp) / "casedup-1.0-py3-none-any.whl",
                {
                    "casedup-1.0.dist-info/METADATA": "Name: casedup\nVersion: 1.0\n",
                    "Foo/mod.py": "X = 1\n",
                    "foo/mod.py": "X = 2\n",
                },
            )
            with self.assertRaisesRegex(ValueError, "Detected collision"):
                inspect_whl.inspect_wheel(case_whl)

            bad_cat = _write_zip(
                pathlib.Path(tmp) / "badcat-1.0-py3-none-any.whl",
                {
                    "badcat-1.0.dist-info/METADATA": "Name: badcat\nVersion: 1.0\n",
                    "badcat-1.0.data/unknown_scheme/file.txt": "hi\n",
                },
            )
            with self.assertRaisesRegex(ValueError, "Unknown \\.data category"):
                inspect_whl.inspect_wheel(bad_cat)

    def test_cli_entrypoints_and_error_reporting(self):
        with tempfile.TemporaryDirectory() as tmp:
            not_a_zip = pathlib.Path(tmp) / "corrupt.whl"
            not_a_zip.write_text("not a zip", encoding="utf-8")
            stderr = io.StringIO()
            with contextlib.redirect_stderr(stderr):
                rc = inspect_whl.main(["--wheel", str(not_a_zip)])
            self.assertEqual(rc, 1)
            self.assertIn("inspect_whl: failed to inspect", stderr.getvalue())

            good_whl = _write_zip(
                pathlib.Path(tmp) / "cli-1.0-py3-none-any.whl",
                {
                    "cli-1.0.dist-info/METADATA": "Name: cli\nVersion: 1.0\n",
                    "cli/__init__.py": "X = 1\n",
                },
            )
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                rc = inspect_whl.main(["--wheel", str(good_whl)])
            self.assertEqual(rc, 0)
            parsed = json.loads(stdout.getvalue())
            self.assertIn("site-packages/cli/__init__.py", parsed["extracted_files"])

            cli_dest = pathlib.Path(tmp) / "cli_installed"
            action_whl_installer.main(
                ["--wheel", str(good_whl), "--directory", str(cli_dest)]
            )
            self.assertTrue((cli_dest / "site-packages/cli/__init__.py").is_file())

    def test_record_rewriting_and_namespace_inits(self):
        with tempfile.TemporaryDirectory() as tmp:
            whl = _write_zip(
                pathlib.Path(tmp) / "ns-1.0-py3-none-any.whl",
                {
                    "ns-1.0.dist-info/METADATA": "Name: ns\nVersion: 1.0\n",
                    "ns-1.0.dist-info/RECORD": (
                        "ns-1.0.data/scripts/my_script,sha256=abc,12\n"
                        "ns-1.0.data/purelib/ns/sep\u2028file.txt,sha256=ghi,3\n"
                        "ns/sub/mod.py,sha256=def,10\n"
                    ),
                    "ns-1.0.data/scripts/my_script": "#!python\nprint(1)\n",
                    "ns-1.0.data/purelib/ns/sep\u2028file.txt": "ok\n",
                    "ns/sub/mod.py": "VAL = 1\n",
                    "ns/sub/__pycache__/mod.cpython-312.pyc": b"\x00\x01",
                    "pyc_only_dir/ stale.pyc": b"\x00\x01",
                },
            )
            dest = pathlib.Path(tmp) / "out"
            action_whl_installer.install_wheel(
                wheel_path=whl,
                dest_dir=dest,
                srcs_exclude_globs=[],
                data_exclude_globs=["**/*.pyc"],
                create_namespace_inits_flag=True,
                target_os="unix",
            )
            with open(
                dest / "site-packages/ns-1.0.dist-info/RECORD", encoding="utf-8"
            ) as f:
                record_lines = list(f)
            self.assertEqual(
                record_lines,
                [
                    "../../../bin/my_script,sha256=abc,12\n",
                    "ns/sep\u2028file.txt,sha256=ghi,3\n",
                    "ns/sub/mod.py,sha256=def,10\n",
                ],
            )
            self.assertTrue((dest / "site-packages/ns/__init__.py").is_file())
            self.assertTrue((dest / "site-packages/ns/sub/__init__.py").is_file())
            self.assertFalse(
                (dest / "site-packages/ns/sub/__pycache__/__init__.py").exists()
            )
            self.assertFalse((dest / "site-packages/pyc_only_dir/__init__.py").exists())

    def test_precompile_keep_and_omit_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            whl = _write_zip(
                pathlib.Path(tmp) / "pcpkg-1.0-py3-none-any.whl",
                {
                    "pcpkg-1.0.dist-info/METADATA": "Name: pcpkg\nVersion: 1.0\n",
                    "pcpkg-1.0.dist-info/RECORD": (
                        "pcpkg/__init__.py,sha256=abc,10\npcpkg/mod.py,sha256=def,12\n"
                    ),
                    "pcpkg/__init__.py": "from .mod import ANSWER\n",
                    "pcpkg/mod.py": "ANSWER = 42\n",
                },
            )
            pyc_tag = sys.implementation.cache_tag
            py_ver = f"{sys.version_info.major}.{sys.version_info.minor}"

            # 1. precompile=False -> no pycs
            dest_disabled = pathlib.Path(tmp) / "out_disabled"
            action_whl_installer.install_wheel(
                wheel_path=whl,
                dest_dir=dest_disabled,
                precompile=False,
            )
            self.assertEqual(list(dest_disabled.rglob("*.pyc")), [])

            # 2. precompile=True, keep_source -> .py and __pycache__/*.pyc present
            dest_keep = pathlib.Path(tmp) / "out_keep"
            action_whl_installer.install_wheel(
                wheel_path=whl,
                dest_dir=dest_keep,
                precompile=True,
                pyc_tag=pyc_tag,
                precompile_invalidation_mode="checked_hash",
                precompile_source_retention="keep_source",
                python_version=py_ver,
                src_name_prefix="pkg/srcs",
            )
            self.assertTrue((dest_keep / "site-packages/pcpkg/__init__.py").is_file())
            self.assertTrue((dest_keep / "site-packages/pcpkg/mod.py").is_file())
            self.assertTrue(
                (
                    dest_keep
                    / f"site-packages/pcpkg/__pycache__/__init__.{pyc_tag}.pyc"
                ).is_file()
            )
            self.assertTrue(
                (
                    dest_keep / f"site-packages/pcpkg/__pycache__/mod.{pyc_tag}.pyc"
                ).is_file()
            )
            record_keep = (
                dest_keep / "site-packages/pcpkg-1.0.dist-info/RECORD"
            ).read_text(encoding="utf-8")
            self.assertIn("pcpkg/mod.py,sha256=def,12\n", record_keep)
            self.assertIn(f"pcpkg/__pycache__/mod.{pyc_tag}.pyc,,\n", record_keep)

            # 3. precompile=True, omit_source -> .py removed, only foo.pyc written (no __pycache__)
            dest_omit = pathlib.Path(tmp) / "out_omit"
            action_whl_installer.install_wheel(
                wheel_path=whl,
                dest_dir=dest_omit,
                precompile=True,
                pyc_tag=pyc_tag,
                precompile_invalidation_mode="unchecked_hash",
                precompile_source_retention="omit_source",
                python_version=py_ver,
                src_name_prefix="pkg/srcs",
            )
            self.assertEqual(list(dest_omit.rglob("*.py")), [])
            self.assertFalse((dest_omit / "site-packages/pcpkg/__pycache__").exists())
            self.assertTrue((dest_omit / "site-packages/pcpkg/__init__.pyc").is_file())
            self.assertTrue((dest_omit / "site-packages/pcpkg/mod.pyc").is_file())
            record_omit = (
                dest_omit / "site-packages/pcpkg-1.0.dist-info/RECORD"
            ).read_text(encoding="utf-8")
            self.assertNotIn("pcpkg/mod.py,", record_omit)
            self.assertNotIn("__pycache__", record_omit)
            self.assertIn("pcpkg/mod.pyc,,\n", record_omit)

            sp_str = str(dest_omit / "site-packages")
            sys.path.insert(0, sp_str)
            try:
                sys.modules.pop("pcpkg", None)
                sys.modules.pop("pcpkg.mod", None)
                spec = importlib.util.find_spec("pcpkg")
                self.assertIsNotNone(spec)
                pcpkg = importlib.import_module("pcpkg")
                self.assertEqual(pcpkg.ANSWER, 42)
            finally:
                sys.path.remove(sp_str)
                sys.modules.pop("pcpkg", None)
                sys.modules.pop("pcpkg.mod", None)

    def test_precompile_syntax_error_and_custom_precompiler(self):
        with tempfile.TemporaryDirectory() as tmp:
            whl = _write_zip(
                pathlib.Path(tmp) / "badpy-1.0-py3-none-any.whl",
                {
                    "badpy-1.0.dist-info/METADATA": "Name: badpy\nVersion: 1.0\n",
                    "badpy-1.0.dist-info/RECORD": (
                        "badpy/__init__.py,sha256=abc,10\nbadpy/py2_only.py,sha256=def,12\n"
                    ),
                    "badpy/__init__.py": "OK = True\n",
                    "badpy/py2_only.py": "print 'py2 syntax'\n",
                },
            )
            pyc_tag = sys.implementation.cache_tag
            py_ver = f"{sys.version_info.major}.{sys.version_info.minor}"

            # 1. In-process py_compile with omit_source retains py2_only.py and writes stub py2_only.pyc
            dest_inproc = pathlib.Path(tmp) / "out_inproc"
            action_whl_installer.install_wheel(
                wheel_path=whl,
                dest_dir=dest_inproc,
                precompile=True,
                pyc_tag=pyc_tag,
                precompile_source_retention="omit_source",
                python_version=py_ver,
            )
            self.assertTrue(
                (dest_inproc / "site-packages/badpy/__init__.pyc").is_file()
            )
            self.assertFalse((dest_inproc / "site-packages/badpy/__init__.py").exists())
            self.assertTrue((dest_inproc / "site-packages/badpy/py2_only.py").is_file())
            self.assertTrue(
                (dest_inproc / "site-packages/badpy/py2_only.pyc").is_file()
            )
            sp_inproc = str(dest_inproc / "site-packages")
            sys.path.insert(0, sp_inproc)
            try:
                sys.modules.pop("badpy", None)
                sys.modules.pop("badpy.py2_only", None)
                with self.assertRaises(SyntaxError):
                    importlib.import_module("badpy.py2_only")
                # Also verify the stub .pyc directly (as loaded in a venv that symlinks only .pyc):
                loader = importlib.machinery.SourcelessFileLoader(
                    "badpy.py2_only",
                    str(dest_inproc / "site-packages/badpy/py2_only.pyc"),
                )
                spec = importlib.util.spec_from_loader("badpy.py2_only", loader)
                assert spec is not None  # type assert
                mod = importlib.util.module_from_spec(spec)
                with self.assertRaises(SyntaxError) as cm:
                    loader.exec_module(mod)
                self.assertEqual(
                    cm.exception.filename, "site-packages/badpy/py2_only.py"
                )
                self.assertEqual(cm.exception.lineno, 1)
                self.assertNotIn(tmp, cm.exception.msg)
            finally:
                sys.path.remove(sp_inproc)
                sys.modules.pop("badpy", None)
                sys.modules.pop("badpy.py2_only", None)

            # 2. Custom executable precompiler tool: batched on valid wheel, bisected on bad file
            count_file = pathlib.Path(tmp) / "count.txt"
            fake_py = pathlib.Path(tmp) / "fake_precompiler_impl.py"
            fake_py.write_text(
                "import pathlib, py_compile, sys\n"
                f"count_p = pathlib.Path({str(count_file)!r})\n"
                "n = int(count_p.read_text()) if count_p.exists() else 0\n"
                "count_p.write_text(str(n + 1))\n"
                "args = pathlib.Path(sys.argv[1][1:]).read_text().splitlines()\n"
                "srcs = [args[i + 1] for i, a in enumerate(args) if a == '--src']\n"
                "pycs = [args[i + 1] for i, a in enumerate(args) if a == '--pyc']\n"
                "for s, c in zip(srcs, pycs):\n"
                "    py_compile.compile(s, cfile=c, doraise=True)\n",
                encoding="utf-8",
            )
            fake_tool = pathlib.Path(tmp) / "fake_precompiler.sh"
            fake_tool.write_text(
                f'#!/bin/sh\nexec "{sys.executable}" "{fake_py}" "$@"\n',
                encoding="utf-8",
            )
            fake_tool.chmod(0o755)

            valid_whl = _write_zip(
                pathlib.Path(tmp) / "goodpy-1.0-py3-none-any.whl",
                {
                    "goodpy-1.0.dist-info/METADATA": "Name: goodpy\nVersion: 1.0\n",
                    "goodpy-1.0.dist-info/RECORD": (
                        "goodpy/a.py,sha256=abc,4\ngoodpy/b.py,sha256=def,4\n"
                    ),
                    "goodpy/a.py": "A = 1\n",
                    "goodpy/b.py": "B = 2\n",
                },
            )
            dest_batch = pathlib.Path(tmp) / "out_batch"
            action_whl_installer.install_wheel(
                wheel_path=valid_whl,
                dest_dir=dest_batch,
                precompile=True,
                pyc_tag=pyc_tag,
                precompile_source_retention="keep_source",
                python_version=py_ver,
                precompiler_tool=fake_tool,
            )
            self.assertEqual(int(count_file.read_text()), 1)
            self.assertTrue(
                (
                    dest_batch / f"site-packages/goodpy/__pycache__/a.{pyc_tag}.pyc"
                ).is_file()
            )
            self.assertTrue(
                (
                    dest_batch / f"site-packages/goodpy/__pycache__/b.{pyc_tag}.pyc"
                ).is_file()
            )

            # Bisection fallback when 1 of 8 files fails: 1 + 2*log2(8) = 7 spawns (< 1 + 8 = 9).
            eight_whl = _write_zip(
                pathlib.Path(tmp) / "eight-1.0-py3-none-any.whl",
                {
                    "eight-1.0.dist-info/METADATA": "Name: eight\nVersion: 1.0\n",
                    "eight-1.0.dist-info/RECORD": "",
                    "eight/f0.py": "X = 0\n",
                    "eight/f1.py": "X = 1\n",
                    "eight/f2.py": "X = 2\n",
                    "eight/f3.py": "X = 3\n",
                    "eight/f4.py": "X = 4\n",
                    "eight/f5_bad.py": "print 'py2'\n",
                    "eight/f6.py": "X = 6\n",
                    "eight/f7.py": "X = 7\n",
                },
            )
            count_file.unlink()
            dest_fallback = pathlib.Path(tmp) / "out_fallback"
            action_whl_installer.install_wheel(
                wheel_path=eight_whl,
                dest_dir=dest_fallback,
                precompile=True,
                pyc_tag=pyc_tag,
                precompile_source_retention="keep_source",
                python_version=py_ver,
                precompiler_tool=fake_tool,
            )
            self.assertEqual(int(count_file.read_text()), 7)
            self.assertTrue(
                (
                    dest_fallback / f"site-packages/eight/__pycache__/f0.{pyc_tag}.pyc"
                ).is_file()
            )
            self.assertTrue(
                (
                    dest_fallback
                    / f"site-packages/eight/__pycache__/f5_bad.{pyc_tag}.pyc"
                ).is_file()
            )


if __name__ == "__main__":
    unittest.main()

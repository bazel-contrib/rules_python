"""Integration test for prebuilt tool toolchain configuration."""

import hashlib
import json
import shutil
import unittest

from python.runfiles import runfiles
from tests.integration import runner

_USE_RUST_FLAG = "--@rules_python//python/private/toolchains:use_rust_tools=yes"


class PrebuiltToolchainTest(runner.TestCase):
    def setUp(self):
        super().setUp()
        rf = runfiles.CreateOrRaise()
        rupyru_box = (rf.root() / "rules_python/crates/rupyru-box/rupyru-box").resolve()
        self.assertTrue(
            rupyru_box.is_file(),
            f"Expected rupyru-box binary at {rupyru_box}",
        )
        sha256 = hashlib.sha256(rupyru_box.read_bytes()).hexdigest()

        orig_rules_python = self.repo_root.parent.parent.parent
        self.rules_python_dir = self.test_tmp_dir / "rules_python"
        shutil.copytree(
            orig_rules_python,
            self.rules_python_dir,
            ignore=shutil.ignore_patterns("tests", "bazel-*"),
        )

        # Simulate a release archive where tool dependencies (such as
        # rules_rust) are dev-only and prebuilt toolchains are configured via
        # artifacts_manifest.bzl.
        module_bazel = self.rules_python_dir / "MODULE.bazel"
        module_content = module_bazel.read_text(encoding="utf-8")
        self.assertIn("\nTOOL_DEPS_DEV_ONLY = False\n", module_content)
        module_bazel.write_text(
            module_content.replace(
                "\nTOOL_DEPS_DEV_ONLY = False\n",
                "\nTOOL_DEPS_DEV_ONLY = True\n",
            ),
            encoding="utf-8",
        )

        manifest = {
            "artifacts": {
                "rupyru-box": [
                    {
                        "exec_compatible_with": [
                            "@platforms//os:windows",
                        ],
                        "name": "rupyru_box_unmatched",
                        "sha256": "0" * 64,
                        "urls": ["https://invalid.example.com/should-not-be-fetched"],
                    },
                    {
                        "exec_compatible_with": [],
                        "name": "rupyru_box_prebuilt",
                        "sha256": sha256,
                        "urls": [rupyru_box.as_uri()],
                    },
                ],
            },
        }
        manifest_path = self.rules_python_dir / "python/private/artifacts_manifest.bzl"
        manifest_path.write_text(
            f'ARTIFACTS_MANIFEST_JSON = """{json.dumps(manifest, indent=1)}"""\n',
            encoding="utf-8",
        )

    def test_prebuilt_rupyru_box_toolchain(self):
        override_flag = f"--override_module=rules_python={self.rules_python_dir}"

        self.run_bazel(
            "test",
            override_flag,
            _USE_RUST_FLAG,
            "//:zipapp_test",
        )

        aquery_res = self.run_bazel(
            "aquery",
            override_flag,
            _USE_RUST_FLAG,
            "mnemonic(PyZipAppCreateExecutableZip, //:zipapp_test)",
        )
        self.assert_result_matches(
            aquery_res,
            r"rules_python_rupyru_box_prebuilt_file/file/downloaded",
        )


if __name__ == "__main__":
    unittest.main()

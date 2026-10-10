# Copyright 2024 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import unittest

from tests.integration import runner


class CustomCommandsTest(runner.TestCase):
    # Regression test for https://github.com/bazel-contrib/rules_python/issues/1840
    def test_run_build_python_zip_false(self):
        result = self.run_bazel(
            "run",
            "--build_python_zip=false",
            "--@rules_python//python/config_settings:build_python_zip=false",
            "//:bin",
        )
        self.assert_result_matches(result, "bazel-out")

    # Regression test for https://github.com/bazel-contrib/rules_python/issues/4198
    def test_runtime_files_exclude_pycache_symlinks(self):
        result = self.run_bazel(
            "cquery",
            "--repo_env=RULES_PYTHON_PYCACHE_DIR=/dev/null",
            "--output=files",
            "deps(//:bin)",
        )
        pycache = [f for f in result.stdout.splitlines() if "__pycache__" in f]
        self.assertEqual(pycache, [])


if __name__ == "__main__":
    # Enabling this makes the runner log subprocesses as the test goes along.
    # logging.basicConfig(level = "INFO")
    unittest.main()

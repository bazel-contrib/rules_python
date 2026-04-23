# Copyright 2025 The Bazel Authors. All rights reserved.
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

"""Integration test for python.override(toolchain_target_settings=...).

Verifies that when all default toolchains are gated behind a config_setting,
requesting a different (unregistered) toolchain family produces a toolchain
resolution error instead of silently falling back to the default toolchains.
"""

import unittest

from tests.integration import runner


class ToolchainTargetSettingsTest(runner.TestCase):
    def test_prebuilt_family_resolves(self):
        """Building with the 'prebuilt' family should succeed.

        The default toolchains have target_settings = [":is_prebuilt"],
        and the transition sets //:family=prebuilt, so the config_setting
        matches and toolchain resolution finds the default 3.13 toolchain.
        """
        self.run_bazel("test", "//:prebuilt_test")

    def test_custom_family_without_toolchain_fails(self):
        """Building with the 'custom' family should fail.

        No toolchains have target_settings = [":is_custom"], and the default
        toolchains are gated behind ":is_prebuilt" (via toolchain_target_settings),
        so toolchain resolution should fail with no matching toolchain.
        """
        result = self.run_bazel(
            "build", "//:custom_no_toolchain_test", check=False
        )
        self.assertNotEqual(result.exit_code, 0, "Expected build to fail")
        self.assert_result_matches(
            result,
            r"No matching toolchains found for types",
        )


if __name__ == "__main__":
    unittest.main()

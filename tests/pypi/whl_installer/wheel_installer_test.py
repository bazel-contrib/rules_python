# Copyright 2023 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import json
import os
import shutil
import tempfile
import unittest
from pathlib import Path

from python.private.pypi.whl_installer import wheel_installer


class TestWhlFilegroup(unittest.TestCase):
    def setUp(self) -> None:
        self.wheel_name = "example_minimal_package-0.0.1-py3-none-any.whl"
        self.wheel_dir = tempfile.mkdtemp()
        self.wheel_path = os.path.join(self.wheel_dir, self.wheel_name)
        shutil.copy(os.path.join("examples", "wheel", self.wheel_name), self.wheel_dir)

    def tearDown(self):
        shutil.rmtree(self.wheel_dir)

    def test_wheel_exists(self) -> None:
        wheel_installer._extract_wheel(
            Path(self.wheel_path),
            enable_implicit_namespace_pkgs=False,
            installation_dir=Path(self.wheel_dir),
        )

        want_files = [
            "metadata.json",
            "site-packages",
            self.wheel_name,
        ]
        self.assertEqual(
            sorted(want_files),
            sorted(
                [
                    str(p.relative_to(self.wheel_dir))
                    for p in Path(self.wheel_dir).glob("*")
                ]
            ),
        )
        with open("{}/metadata.json".format(self.wheel_dir)) as metadata_file:
            metadata_file_content = json.load(metadata_file)

        want = dict(
            entry_points=[],
            python_version="3.11.11",
        )
        self.assertEqual(want, metadata_file_content)


if __name__ == "__main__":
    unittest.main()

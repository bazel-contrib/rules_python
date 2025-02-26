# Copyright 2018 The Bazel Authors. All rights reserved.
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

import os
import unittest

from python.runfiles import runfiles


class RunfilesTest(unittest.TestCase):
    """Unit tests for `rules_python.python.runfiles.Runfiles`."""

    def testCreatesDirectoryBasedRunfiles(self) -> None:
        r = runfiles.Create()
        repo = r.CurrentRepository() or "_main"
        bin_location = r.Rlocation(os.path.join(repo,"tests/runfiles/bin_with_runfiles_test.py"))
        self.maxDiff = None
        self.assertEqual(bin_location, __file__)

if __name__ == "__main__":
    unittest.main()

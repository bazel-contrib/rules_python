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

import hashlib
import os
import tempfile
import unittest
from unittest import mock

from tools.private.zipapp import zip_main_maker

class ZipMainMakerTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)

    def test_creates_zip_main(self):
        template_path = os.path.join(self.temp_dir.name, "template.py")
        with open(template_path, "w", encoding="utf-8") as f:
            f.write("hash=%APP_HASH%\nfoo=%FOO%\n")
        
        output_path = os.path.join(self.temp_dir.name, "output.py")
        
        file1_path = os.path.join(self.temp_dir.name, "file1.txt")
        with open(file1_path, "wb") as f:
            f.write(b"content1")
            
        file2_path = os.path.join(self.temp_dir.name, "file2.txt")
        with open(file2_path, "wb") as f:
            f.write(b"content2")
            
        manifest_path = os.path.join(self.temp_dir.name, "manifest.txt")
        with open(manifest_path, "w", encoding="utf-8") as f:
            f.write(f"rf-file|1|file1.txt|{file1_path}\n")
            f.write(f"rf-file|0|file2.txt|{file2_path}\n")
            
        argv = [
            "zip_main_maker.py",
            "--template", template_path,
            "--output", output_path,
            "--substitution", "%FOO%=bar",
            "--hash_files_manifest", manifest_path,
        ]
        
        with mock.patch("sys.argv", argv):
            zip_main_maker.main()
            
        # Calculate expected hash
        h = hashlib.sha256()
        line1 = f"rf-file|1|file1.txt|{file1_path}"
        line2 = f"rf-file|0|file2.txt|{file2_path}"
        
        # Sort lines like the program does
        lines = sorted([line1, line2])
        for line in lines:
            h.update(line.encode("utf-8"))
            parts = line.split("|")
            path = parts[-1]
            with open(path, "rb") as f:
                h.update(f.read())
                
        expected_hash = h.hexdigest()
        
        with open(output_path, "r", encoding="utf-8") as f:
            content = f.read()
            
        self.assertEqual(content, f"hash={expected_hash}\nfoo=bar\n")

if __name__ == "__main__":
    unittest.main()

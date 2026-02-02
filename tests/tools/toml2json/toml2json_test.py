import io
import json
import os
import sys
import tempfile
import unittest
from unittest.mock import patch

from tools.toml2json import toml2json

class Toml2JsonTest(unittest.TestCase):

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)

    def _create_temp_toml_file(self, content):
        fd, path = tempfile.mkstemp(suffix=".toml", dir=self.temp_dir.name)
        with os.fdopen(fd, "wb") as f:
            f.write(content)
        return path

    def test_basic_conversion(self):
        toml_content = b"""
[owner]
name = "Tom Preston-Werner"
dob = 1979-05-27T07:32:00-08:00
"""
        expected_json = {
            "owner": {
                "name": "Tom Preston-Werner",
                "dob": "1979-05-27T07:32:00-08:00"
            }
        }
        
        toml_file_path = self._create_temp_toml_file(toml_content)

        with patch('sys.stdout', new=io.StringIO()) as mock_stdout:
            with patch('sys.argv', ['toml2json.py', toml_file_path]):
                toml2json.main()
                actual_json = json.loads(mock_stdout.getvalue())
                self.assertEqual(actual_json, expected_json)

    def test_invalid_toml(self):
        toml_content = b"""
[owner
name = "Tom Preston-Werner"
"""

        toml_file_path = self._create_temp_toml_file(toml_content)

        with patch('sys.stderr', new=io.StringIO()) as mock_stderr:
            with patch('sys.stdout', new=io.StringIO()): # We don't expect stdout for errors
                with patch('sys.exit') as mock_exit:
                    with patch('sys.argv', ['toml2json.py', toml_file_path]):
                        toml2json.main()
                        mock_exit.assert_called_with(1)
                    self.assertIn("Error decoding TOML", mock_stderr.getvalue())


if __name__ == '__main__':
    unittest.main()

import datetime
import platform
import sys
import unittest


class BasicTest(unittest.TestCase):
    def test_basic(self):
        print("Hello World from Python {}!".format(sys.version))
        print("Interpreter executable path: {}".format(sys.executable))

        # Verify that the hermetic interpreter inside Bazel's output/sandbox tree is used
        self.assertIn(".cache/bazel", sys.executable)

        # Verify that the exact custom version (3.11.15) parsed from the manifest is used
        self.assertEqual(sys.version_info[:3], (3, 11, 15))

        # Verify that the exact build version (20260414) parsed from the manifest is used
        buildno, builddate = platform.python_build()
        date_str = " ".join(builddate.split()[:3])
        dt = datetime.datetime.strptime(date_str, "%b %d %Y")
        formatted_date = dt.strftime("%Y%m%d")
        self.assertEqual(formatted_date, "20260414")


if __name__ == "__main__":
    unittest.main()

import unittest

class ImportingRunfilestest(unittest.TestCase):

    def test_import_python(self):
        import python
        import python.runfiles
        import python.runfiles.runfiles

        # Import the canonical names second to verify they result in
        # the same module objects.
        # They're imported one-by-one to make failures easier to identify.
        import rules_python
        import rules_python.python
        import rules_python.python.runfiles
        import rules_python.python.runfiles.runfiles

        self.assertIs(rules_python.python, python)
        self.assertIs(rules_python.python.runfiles, python.runfiles)
        self.assertIs(rules_python.python.runfiles.runfiles, python.runfiles.runfiles)


if __name__ == "__main__":
    unittest.main()

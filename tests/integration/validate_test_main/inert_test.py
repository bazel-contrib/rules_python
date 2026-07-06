import unittest


class InertTest(unittest.TestCase):
    def test_nothing_runs(self):
        # This test case is never executed because nothing invokes a runner.
        self.assertTrue(True)

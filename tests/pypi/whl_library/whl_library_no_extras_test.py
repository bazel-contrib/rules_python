import unittest


class NoExtrasTest(unittest.TestCase):
    def test_extras_not_propagated(self):
        import pkg

        self.assertEqual(pkg.WITH_EXTRAS, False)


if __name__ == "__main__":
    unittest.main()

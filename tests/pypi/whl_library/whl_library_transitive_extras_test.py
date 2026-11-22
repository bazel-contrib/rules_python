import unittest


class TransitiveExtrasTest(unittest.TestCase):
    def test_extras_from_metadata_propagated(self):
        import consumer

        self.assertEqual(consumer.WITH_EXTRAS, True)


if __name__ == "__main__":
    unittest.main()

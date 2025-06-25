import unittest


class VerifyFilestest(unittest.TestCase):

    def test_stuff(self):
        import somepkg
        import somepkg.a
        import somepkg.subpkg
        import somepkg.subpkg.b


if __name__ == "__main__":
    unittest.main()

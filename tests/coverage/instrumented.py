"""The program for which the coverage is collected."""

from tests.coverage import lib

if __name__ == "__main__":
    print(lib.covered(True))

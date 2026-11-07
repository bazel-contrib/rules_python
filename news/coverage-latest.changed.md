(coverage) The bundled coverage.py was updated to 7.17.2 for Python 3.11 and
later. Python 3.9 and 3.10 keep using coverage.py 7.10.7, which is the last
version that supports them. Free-threaded Python 3.13 toolchains now use the
pure Python coverage.py wheel because coverage.py 7.17 does not ship
free-threaded 3.13 wheels.

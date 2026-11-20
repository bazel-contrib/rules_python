(uv) The `.update` target of {obj}`lock` now refuses arguments and prints the
equivalent `.run` command, which passes them to `uv`. It used to accept and drop
them, so `--upgrade-package` reported success without upgrading anything.

(pypi) Fixed {obj}`pip.default` so setting `index_url = ""` disables the Simple
API downloader and falls back to `pip` instead of being ignored.

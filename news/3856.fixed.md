(pypi) The {attr}`pip.parse.experimental_index_url` is no longer passed to the
wheel repositories with the environment variables expanded, so credentials
stored in them do not leak into the lock file.

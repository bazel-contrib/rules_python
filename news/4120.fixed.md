(pypi) Fixed wheel selection logic so that pure-Python wheels (`none` ABI tag
and `any` platform tag) match target platform configurations properly, and
fixed prerelease Python version parsing in `requirements_files_by_platform`.

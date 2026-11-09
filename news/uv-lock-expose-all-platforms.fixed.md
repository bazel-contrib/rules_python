(pypi) Only include `uv.lock` packages in `all_requirements`,
`all_whl_requirements`, and `all_data_requirements` when they resolve across
all configured target platforms in {obj}`pip.parse`.

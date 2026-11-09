(pypi) {attr}`pip.parse.target_platforms` accepts `"*"` to evaluate the
requirements for all of the platforms configured with {obj}`pip.default`. With
{attr}`pip.parse.uv_lock`, the `none-any` wheel of a package is also used for
the platforms that are not configured.

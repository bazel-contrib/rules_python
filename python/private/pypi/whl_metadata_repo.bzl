""

def _impl(rctx):
    fail(rctx.name)

whl_metadata_repo = repository_rule(
    implementation = _impl,
    attrs = {
    },
)

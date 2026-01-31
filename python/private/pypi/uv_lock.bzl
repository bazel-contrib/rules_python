load("//python/private/pypi:pypi_repo_utils.bzl", "pypi_repo_utils")

def _convert_uv_lock_to_json(mrctx, attr, logger):
    python_interpreter = pypi_repo_utils.resolve_python_interpreter(
        mrctx,
        python_interpreter_target = attr._python_interpreter_target,
    )
    toml2json = mrctx.path(attr._toml2json)
    src_path = mrctx.path(attr.srcs[0])

    stdout = pypi_repo_utils.execute_checked_stdout(
        mrctx,
        logger = logger,
        op = "toml2json",
        python = python_interpreter,
        arguments = [
            str(toml2json),
            str(src_path),
        ],
        srcs = [toml2json, src_path],
    )
    return stdout

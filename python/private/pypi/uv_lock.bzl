load("//python/private/pypi:pypi_repo_utils.bzl", "pypi_repo_utils")

def convert_uv_lock_to_json(mrctx, attr, logger, python_interpreter = None):
    """Converts a uv.lock file to json.

    Args:
        mrctx: a module_ctx or repository_ctx object.
        attr: The attribute struct for mrctx. It must have an
            `_python_interpreter_target` attribute of the interpreter
            to use.
        logger: a logger object to use
        python_interpreter: (optional) The resolved python interpreter object.

    Returns:
        The command output, which is a json string.
    """
    if not python_interpreter:
        python_interpreter_target = getattr(attr, "_python_interpreter_target", None)
        if not python_interpreter_target:
            python_interpreter_target = getattr(attr, "python_interpreter_target", None)

        python_interpreter = pypi_repo_utils.resolve_python_interpreter(
            mrctx,
            python_interpreter_target = python_interpreter_target,
        )
    toml2json = mrctx.path(attr._toml2json)
    if hasattr(attr, "uv_lock") and attr.uv_lock:
        src_path = mrctx.path(attr.uv_lock)
    else:
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

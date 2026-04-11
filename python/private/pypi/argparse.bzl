"""A small set of utilities for parsing pip args."""

def _get_pip_args(args, *arg_names, value = None, repeated = False):
    set_next = False
    if repeated:
        value = [] + (value or [])

    for arg in (args or []):
        if arg in arg_names:
            set_next = True
            continue

        val = None
        if set_next:
            set_next = False
            val = arg
        else:
            for arg_name in arg_names:
                start = "{}=".format(arg_name)

                if arg.startswith(start):
                    val = arg[len(start):]
                    break

            if val == None:
                continue

        if repeated:
            if val not in value:
                value.append(val)
        else:
            value = val

    return value

argparse = struct(
    index_url = lambda args, default: _get_pip_args(args, "-i", "--index-url", value = default),
    extra_index_url = lambda args, default: _get_pip_args(args, "--extra-index-url", value = default, repeated = True),
    platform = lambda args, default: _get_pip_args(args, "--platform", value = default, repeated = True),
)

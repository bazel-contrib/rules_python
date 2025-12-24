:::{default-domain} bzl
:::

# How to integrate a debugger

This guide explains how to use the {obj}`--debugger` flag to integrate a debugger
with your Python applications built with `rules_python`.

## Basic Usage

The {obj}`--debugger` flag allows you to inject an extra dependency into `py_test`
and `py_binary` targets so that they have a custom debugger available at
runtime. The flag is roughly equivalent to manually adding it to `deps` of
the target under test.

To use the debugger, you typically provide the `--debugger` flag to your `bazel run` command.

Example command line:

```bash
bazel run --@rules_python//python/config_settings:debugger=@pypi//pudb \
    //path/to:my_python_binary
```

This will launch the Python program with the `@pypi//pudb` dependency added.

The exact behavior (e.g., waiting for attachment, breaking at the first line)
depends on the specific debugger and its configuration.

:::{note}
The specified target must be in the requirements.txt file used with
`pip.parse()` to make it available to Bazel.
:::

## Python `PYTHONBREAKPOINT` Environment Variable

For more fine-grained control over debugging, especially for programmatic breakpoints,
you can leverage the Python built-in `breakpoint()` function and the
`PYTHONBREAKPOINT` environment variable.

The `breakpoint()` built-in function, available since Python 3.7,
can be called anywhere in your code to invoke a debugger. The `PYTHONBREAKPOINT`
environment variable can be set to specify which debugger to use.

For example, to use `pdb` (the Python Debugger) when `breakpoint()` is called:

```bash
PYTHONBREAKPOINT=pudb.set_trace bazel run \
    --@rules_python//python/config_settings:debugger=@pypi//pudb \
    //path/to:my_python_binary
```

For more details on `PYTHONBREAKPOINT`, refer to the [Python documentation](https://docs.python.org/3/library/functions.html#breakpoint).

## Setting a default debugger

By adding settings to your user or project `.bazelrc` files, you can have
these settings automatically added to your bazel invocations. e.g.

```
common --@rules_python//python/config_settings:debugger=@pypi//pudb
common --test_env=PYTHONBREAKPOINT=pudb.set_trace
```

Note that `--test_env` isn't strictly necessary. The `py_test` and `py_binary`
rules will respect the `PYTHONBREAKPOINT` environment variable in your shell.

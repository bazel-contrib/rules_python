# Environment Variables

::::{envvar} RULES_PYTHON_ADDITIONAL_INTERPRETER_ARGS

This variable allows for additional arguments to be provided to the Python interpreter
at bootstrap time. If
`RULES_PYTHON_ADDITIONAL_INTERPRETER_ARGS` were provided as `-Xaaa`, then the command
would be:

```
python -Xaaa /path/to/file.py
```

This feature is useful for the integration of debuggers. For example,
it would be possible to configure `RULES_PYTHON_ADDITIONAL_INTERPRETER_ARGS` to
be set to `/path/to/debugger.py --port 12344 --file`, resulting
in the command executed being:

```
python /path/to/debugger.py --port 12345 --file /path/to/file.py
```

The Bash entry point parses the first line with `read -a` and places these
arguments before the target's `interpreter_args`. Python entry points use
`shlex.split` and place them after the target arguments. This preserves each
entry point's existing precedence. The variable is removed before the
application runs, so nested launchers do not apply it again.

:::{seealso}
The {bzl:obj}`interpreter_args` attribute.

The guide on {any}`How to integrate a debugger`
:::

:::{versionadded} 1.3.0
:::
:::{versionchanged} 1.7.0
Support added for {bzl:flag}`--bootstrap_impl=system_python`.
:::
:::{versionchanged} VERSION_NEXT_PATCH
Target and additional interpreter arguments also apply to `python app.zip`.
:::

::::

:::{envvar} RULES_PYTHON_BOOTSTRAP_VERBOSE

When `1`, debug information about bootstrapping of a program is printed to
stderr. Temporary runtime directories are retained to help diagnose failures.
:::

:::{envvar} RULES_PYTHON_BZLMOD_DEBUG

When `1`, bzlmod extensions will print debug information about what they're
doing. This is mostly useful for development to debug errors.
:::

:::{envvar} RULES_PYTHON_DEPRECATION_WARNINGS

When `1`, `rules_python` will warn users about deprecated functionality that will
be removed in a subsequent major `rules_python` version. Defaults to `0` if unset.
:::

::::{envvar} RULES_PYTHON_EXTRACT_ROOT

Directory to use as the root for creating files necessary for bootstrapping so
that a binary can run.

Applies to runtime-created virtual environments and to `py_zipapp_binary` and
`py_zipapp_test`. Legacy executable ZIPs always use temporary extraction; their
virtual environments cannot persist because they refer to that extraction.

When set, a binary reuses files beneath this directory. The caller owns their
lifetime and must arrange cleanup. ZIP applications prepare a unique staging
directory and publish it only after setup succeeds. Concurrent launches reuse
the completed result. Startup refuses an incomplete existing cache rather than
removing files another process may be using. Use a fresh extract root if an
existing entry is damaged.

Each new cache entry is a directory symlink to a completed image in a hidden
backing directory beside it. Publishing the symlink cannot replace another
entry, including one created concurrently. The backing belongs to the caller
once published. Removing just the symlink does not reclaim its image; clean
the extract root when its applications are no longer running. Older cache
entries stored directly as directories remain readable.

ZIP cache identities include application files, permissions, bootstrap code,
interpreter options and resolved external-runtime facts. Updating a binary can
leave older cache entries behind. Shell and Python entry points share the same
image identity. Published directories follow the caller's umask.

When unset, bootstraps create temporary runtime directories. Bash entry points
use `TMPDIR` or `/tmp`; Python entry points follow `tempfile`'s directory
selection. On POSIX, an independent process removes these directories
asynchronously after the original interpreter PID exits, including across
exec. The application keeps its native PID, signal delivery and terminal job.
Windows waits for the application child before removing its runtime. Console
Ctrl-C is delivered by Windows; the bootstrap waits for the application's own
cleanup and exit status without forwarding another interrupt.

The temporary lifetime ends with the original interpreter, even if a forked
child outlives it. Such applications need a persistent extract root. Linux
namespace PID 1 and child subreapers can adopt the cleanup process; waiting for
every child can then block until application exit. Persistent extraction avoids
that process. Namespace or cgroup shutdown can kill it before removal finishes,
and SIGKILL during setup before registration cannot guarantee cleanup. On
systems without a native exit watch or suitable Linux procfs, PID reuse can
delay removal.

The lifetime and publication behavior above applies to the default application
launchers. Raw templates and older custom rules exposing only `PyExecutableInfo`
retain their existing behavior. Their Windows ZIP adapter re-extracts a persistent
cache on every launch; directory links can make a repeated launch fail. Use
temporary extraction for that compatibility path.

:::{versionadded} 1.2.0
:::

:::{versionchanged} VERSION_NEXT_PATCH
Ordinary and ZIP entry points preserve native POSIX execution and share
failure-safe temporary cleanup. ZIP caches are published after preparation and
include bootstrap inputs in their identity.
:::
::::

:::{envvar} RULES_PYTHON_GAZELLE_VERBOSE

When `1`, debug information from Gazelle is printed to stderr.
::::

:::{envvar} RULES_PYTHON_PIP_ISOLATED

Determines if `--isolated` is used with pip.

Valid values:
* `0` and `false` mean to not use isolated mode
* Other non-empty values mean to use isolated mode.
:::

:::{envvar} RULES_PYTHON_PYCACHE_DIR

Determines the directory that runtime-generated pyc cache files will
be stored in.

This directory may be reused between invocations, depending on the sandboxing
configuration. Setting it to `/dev/null` will, in effect, disable runtime
pyc caching. By setting e.g.
`--sandbox_add_mount_pair=/tmp/rules_python_pycache`, it's possible for pyc
caching to persist across invocations.

**Behavior specific to downloaded runtimes:** 
First `RULES_PYTHON_PYCACHE_DIR` is checked. If set, it is used as-is for
the root pycache directory.

Otherwise, the following environment variables are checked in the following
order. Their values will have `rules_python_pycache` appended to them to form
the root pycache directory:
1. `XDG_CACHE_HOME`.
2. `TMP` (non-Windows) or `TEMP` (Windows).
3. The common platform-specific temporary directory (`/tmp` (non-Windows) or
   `C:\Temp` (Windows)).

If such a diretory cannot be found, or created, then `/dev/null` will be used,
which will effectively disable pyc caching.

:::

:::{envvar} RULES_PYTHON_PYPI_HUB_RESERVED

When `1`, any PyPI hub named `"pypi"` will be renamed to `<module_name>_pypi`
to prevent name collisions with the unified `@pypi` proxy repository, and
a warning is printed indicating that the renaming occurred. If not set (defaulting
to `0`), a warning is printed advising to rename the hub, and the collision
is not resolved.

:::{versionadded} 2.2.0
:::

:::

:::{envvar} RULES_PYTHON_REPO_DEBUG

When `1`, repository rules will print debug information about what they're
doing. This is mostly useful for development to debug errors.
:::

:::{envvar} RULES_PYTHON_REPO_DEBUG_VERBOSITY

Determines the verbosity of logging output for repo rules. Valid values:

* `DEBUG`
* `FAIL`
* `INFO`
* `TRACE`
:::

:::{envvar} RULES_PYTHON_REPO_TOOLCHAIN_VERSION_OS_ARCH

Determines the Python interpreter platform to be used for a particular
interpreter `(version, os, arch)` triple to be used in repository rules.
Replace the `VERSION_OS_ARCH` part with actual values when using, e.g.,
`3_13_0_linux_x86_64`. The version values must have `_` instead of `.` and the
os, arch values are the same as the ones mentioned in the
`//python:versions.bzl` file.
:::

:::{envvar} VERBOSE_COVERAGE

When `1`, debug information about coverage behavior is printed to stderr.
:::

## Removed Environment Variables

:::{versionremoved} 2.1.0
The following environment variables were removed:

* `RULES_PYTHON_ENABLE_PYSTAR`: Used to enable the Starlark implementation of
  core rules.
* `RULES_PYTHON_ENABLE_PIPSTAR`: Used to enable the Starlark implementation of
  PyPI integration.
:::

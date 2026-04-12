# Copyright 2024 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Mocks for repository_ctx, module_ctx, and File objects."""

def mock_path(path, mocked_files = {}):
    """Create a mock path object.

    Args:
        path: The path string.
        mocked_files: A dict of mocked files.

    Returns:
        A struct mocking a path object.
    """
    return struct(
        exists = path in mocked_files,
        basename = path.split("/")[-1],
        dirname = "/".join(path.split("/")[:-1]),
        _path = path,
    )

def mock_file(path, content = ""):
    """Create a mock File object.

    Args:
        path: The path to the file.
        content: The content of the file.

    Returns:
        A struct mocking a File object.
    """
    return struct(
        path = path,
        basename = path.split("/")[-1],
        dirname = "/".join(path.split("/")[:-1]),
        extension = path.split(".")[-1] if "." in path else "",
        is_source = True,
        owner = Label("//:mock"),
        short_path = path,
    )

def mock_mctx(
        *args,
        **kwargs):
    """Create a mock module_ctx object.

    Args:
        *args: Mock modules passed positionally.
        **kwargs: Optional arguments:
            modules: List of mock modules (alternative to positional args).
            environ: Dict of environment variables.
            mocked_files: Dict mapping path strings to content.
            os_name: The OS name.
            arch_name: The architecture name.
            read: Optional read function.
            download: Optional download function.
            report_progress: Optional report_progress function.

    Returns:
        A struct mocking a module_ctx object.
    """
    modules = kwargs.get("modules")
    if modules == None:
        modules = list(args)
    elif type(modules) != "list":
        modules = [modules]

    environ = kwargs.get("environ", {})
    mocked_files = kwargs.get("mocked_files", {})
    os_name = kwargs.get("os_name", "linux")
    arch_name = kwargs.get("arch_name", "x86_64")
    read = kwargs.get("read")
    download = kwargs.get("download")
    report_progress = kwargs.get("report_progress")
    facts = kwargs.get("facts")

    def _read(x, watch = None):
        _ = watch
        path_str = x._path if hasattr(x, "_path") else str(x)
        if path_str not in mocked_files:
            fail("File not found in mocked_files: " + path_str)
        return mocked_files[path_str]

    def _path(x):
        return mock_path(str(x), mocked_files)

    return struct(
        path = _path,
        read = read or _read,
        getenv = environ.get,
        facts = facts,
        os = struct(
            name = os_name,
            arch = arch_name,
        ),
        modules = [
            struct(
                name = modules[0].name,
                tags = modules[0].tags,
                is_root = getattr(modules[0], "is_root", False),
            ),
        ] + [
            struct(
                name = mod.name,
                tags = mod.tags,
                is_root = False,
            )
            for mod in modules[1:]
        ] if modules else [],
        download = download or (lambda *_, **__: struct(
            success = True,
            wait = lambda: struct(
                success = True,
            ),
        )),
        report_progress = report_progress or (lambda _: None),
    )

def mock_rctx(
        attr = {},
        environ = {},
        mocked_files = {},
        os_name = "linux",
        arch_name = "x86_64",
        read = None,
        download = None,
        download_and_extract = None,
        execute = None,
        file = None,
        symlink = None,
        template = None,
        which = None):
    """Create a mock repository_ctx object.

    Args:
        attr: Dict of attributes.
        environ: Dict of environment variables.
        mocked_files: Dict mapping path strings to content.
        os_name: The OS name.
        arch_name: The architecture name.
        read: Optional read function.
        download: Optional download function.
        download_and_extract: Optional download_and_extract function.
        execute: Optional execute function.
        file: Optional file function.
        symlink: Optional symlink function.
        template: Optional template function.
        which: Optional which function.

    Returns:
        A struct mocking a repository_ctx object.
    """

    def _read(x):
        path_str = x._path if hasattr(x, "_path") else str(x)
        if path_str not in mocked_files:
            fail("File not found in mocked_files: " + path_str)
        return mocked_files[path_str]

    def _path(x):
        return mock_path(str(x), mocked_files)

    return struct(
        attr = struct(**attr),
        path = _path,
        read = read or _read,
        os = struct(
            name = os_name,
            arch = arch_name,
        ),
        os_environ = environ,
        download = download,
        download_and_extract = download_and_extract,
        execute = execute,
        file = file,
        symlink = symlink,
        template = template,
        which = which,
    )

def mock_glob_call(*args, **kwargs):
    """Create a struct representing a glob call.

    Args:
        *args: Positional arguments to glob.
        **kwargs: Keyword arguments to glob.

    Returns:
        A struct with glob and kwargs fields.
    """
    return struct(
        glob = args,
        kwargs = kwargs,
    )

def mock_glob():
    """Create a mock glob object.

    Returns:
        A struct with calls and results lists, and a glob function.
    """
    calls = []
    results = []

    def _glob(*args, **kwargs):
        calls.append(mock_glob_call(*args, **kwargs))
        if not results:
            fail("Mock glob missing for invocation: args={} kwargs={}".format(
                args,
                kwargs,
            ))
        return results.pop(0)

    return struct(
        calls = calls,
        results = results,
        glob = _glob,
    )

def mock_select(value, no_match_error = None):
    """A mock select function that returns the value.

    Args:
        value: The value to return.
        no_match_error: Ignored.

    Returns:
        The value.
    """
    _ = no_match_error
    return value

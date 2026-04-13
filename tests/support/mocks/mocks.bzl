"""Mocks for repository_ctx, module_ctx, and File objects."""

def _path_new(path, mock_files = None):
    """Create a mock path object.

    Args:
        path: {type}`string` The path string.
        mock_files: {type}`dict[string, string]` A dict of mocked files.

    Returns:
        {type}`MockPath` A struct mocking a path object.
    """
    mock_files = mock_files or {}
    return struct(
        exists = path in mock_files,
        basename = path.split("/")[-1],
        dirname = "/".join(path.split("/")[:-1]),
        _path = path,
    )

def _file_new(short_path, *, path = None, is_source = True, owner = None):
    """Create a mock File object.

    Args:
        short_path: {type}`string` The short path to the file.
        path: {type}`string` The full path to the file. Defaults to a made
            up exec-root path or the short path if is_source.
        is_source: {type}`bool` Whether the file is a source file.
        owner: {type}`Label|string` The owner label of the file.

    Returns:
        {type}`MockFile` A struct mocking a File object.
    """
    if owner == None:
        owner = Label("//:mock")

    owner_str = str(owner)
    repo_name = owner_str.split("//")[0]

    is_main_repo = repo_name in ("", "@", "@@")

    actual_short_path = short_path
    if not is_main_repo:
        repo_name = repo_name.lstrip("@")
        if not actual_short_path.startswith("../"):
            actual_short_path = "../{}/{}".format(repo_name, short_path)

        if path == None:
            rel_path = short_path
            if rel_path.startswith("../"):
                parts = rel_path.split("/")
                rel_path = "/".join(parts[2:])

            if is_source:
                path = "external/{}/{}".format(repo_name, rel_path)
            else:
                path = "bazel-out/k9-deadbeef/bin/external/{}/{}".format(
                    repo_name,
                    rel_path,
                )
    elif path == None:
        if is_source:
            path = short_path
        else:
            path = "bazel-out/k9-deadbeef/bin/{}".format(short_path)

    return struct(
        path = path,
        basename = path.split("/")[-1],
        dirname = "/".join(path.split("/")[:-1]),
        extension = path.split(".")[-1] if "." in path else "",
        is_source = is_source,
        owner = owner,
        short_path = actual_short_path,
    )

def _tag_new(**kwargs):
    """Create a mock tag.

    Args:
        **kwargs: {type}`dict` The tag attributes.

    Returns:
        {type}`MockTag` A mock tag object.
    """
    return struct(**kwargs)

def _module_new(name, *, is_root = False, **tags):
    """Create a mock module object.

    Args:
        name: {type}`string` The name of the module.
        is_root: {type}`bool` Whether this is the root module.
        **tags: {type}`list[MockTag]` Lists of tag objects.

    Returns:
        {type}`MockModule` A mock module object.
    """
    return struct(
        name = name,
        tags = struct(**tags),
        is_root = is_root,
    )

def _mctx_read(self, x, watch = None):
    _ = watch  # @unused
    path_str = x._path if hasattr(x, "_path") else str(x)
    if path_str not in self.mock_files:
        fail("File not found in mock_files: " + path_str)
    return self.mock_files[path_str]

def _mctx_path(self, x):
    return _path_new(str(x), self.mock_files)

def _get_download_file_name(url, output = ""):
    """Compute the download file name.

    Args:
        url: {type}`string` The URL being downloaded.
        output: {type}`string` The explicit output path, if any.

    Returns:
        {type}`string` The file name.
    """
    if output:
        return str(output)
    return str(url).split("?")[0].split("/")[-1]

def _mctx_download(
        self,
        url,
        output = "",
        sha256 = "",
        executable = False,
        allow_fail = False,
        canonical_id = "",
        auth = {},
        headers = {},
        integrity = "",
        block = True):
    _ = (
        sha256,
        executable,
        allow_fail,
        canonical_id,
        auth,
        headers,
        integrity,
        block,
    )  # @unused
    urls = url if type(url) == "list" else [url]
    for u in urls:
        content = None
        if u in self.mock_downloads:
            content = self.mock_downloads[u]
        elif "*" in self.mock_downloads:
            content = self.mock_downloads["*"]

        if content != None:
            if type(content) == "string":
                out = _get_download_file_name(u, output)
                self.mock_files[out] = content
                return struct(
                    success = True,
                    wait = lambda: struct(success = True),
                )
            else:
                return content(
                    self,
                    u,
                    output,
                    sha256,
                    executable,
                    allow_fail,
                    canonical_id,
                    auth,
                    headers,
                    integrity,
                )

    if not self.mock_downloads:
        return struct(success = True, wait = lambda: struct(success = True))
    return struct(success = False, wait = lambda: struct(success = False))

def _mctx_report_progress(self, message):
    self.report_progress_calls.append(message)
    return None

def _mctx_add_module(self, **kwargs):
    """Add a module to the mock module_ctx.

    Args:
        self: The mock module_ctx.
        **kwargs: Arguments to pass to _module_new.

    Returns:
        {type}`MockModuleCtx` The mock module_ctx.
    """
    module = _module_new(**kwargs)
    if module.is_root and len(self.modules) > 0:
        fail("is_root=True can only be set on the first module in the " +
             "modules list.")
    self.modules.append(module)
    return self

def _mctx_new(
        *args,
        modules = None,
        environ = None,
        mock_files = None,
        mock_downloads = None,
        os_name = "linux",
        arch_name = "x86_64",
        facts = None):
    """Create a mock module_ctx object.

    Args:
        *args: {type}`list[MockModule]` Mock modules passed positionally.
        modules: {type}`list[MockModule]` List of mock modules (alternative
            to positional args).
        environ: {type}`dict[string, string]` Dict of environment variables.
        mock_files: {type}`dict[string, string]` Dict mapping path strings
            to content.
        mock_downloads: {type}`dict[string, string|callable]` Dict mapping
            url to string or callable.
        os_name: {type}`string` The OS name.
        arch_name: {type}`string` The architecture name.
        facts: {type}`dict` Optional facts dict.

    Returns:
        {type}`MockModuleCtx` A struct mocking a module_ctx object.
    """
    modules = list(args) + (modules or [])

    for i, mod in enumerate(modules):
        if getattr(mod, "is_root", False) and i != 0:
            fail("is_root=True can only be set on the first module in the " +
                 "modules list.")

    environ = environ or {}
    mock_files = mock_files or {}
    mock_downloads = mock_downloads or {}

    # buildifier: disable=uninitialized
    self = struct(
        mock_files = mock_files,
        mock_downloads = mock_downloads,
        report_progress_calls = [],
        getenv = environ.get,
        facts = facts,
        os = struct(
            name = os_name,
            arch = arch_name,
        ),
        modules = list(modules),
        path = lambda *a, **k: _mctx_path(self, *a, **k),
        read = lambda *a, **k: _mctx_read(self, *a, **k),
        download = lambda *a, **k: _mctx_download(self, *a, **k),
        report_progress = lambda *a, **k: _mctx_report_progress(self, *a, **k),
        add_module = lambda **k: _mctx_add_module(self, **k),
    )
    return self

def _rctx_read(self, x):
    path_str = x._path if hasattr(x, "_path") else str(x)
    if path_str not in self.mock_files:
        fail("File not found in mock_files: " + path_str)

    val = self.mock_files[path_str]
    for _ in range(10):
        if type(val) == "dict" and val.get("type") == "symlink":
            path_str = val["target"]
            if path_str not in self.mock_files:
                fail("Symlink target not found in mock_files: " + path_str)
            val = self.mock_files[path_str]
        else:
            break

    if type(val) == "dict" and val.get("type") == "symlink":
        fail("Too many symlinks followed")

    return val

def _rctx_path(self, x):
    return _path_new(str(x), self.mock_files)

def _rctx_file(self, path, content = "", executable = True, legacy_utf8 = True):
    _ = executable, legacy_utf8  # @unused
    self.mock_files[str(path)] = content

def _rctx_template(self, path, template, substitutions = {}, executable = True):
    _ = executable  # @unused
    template_str = str(template)
    if template_str not in self.mock_files:
        fail("Template file not found: " + template_str)

    content = self.mock_files[template_str]
    for key, value in substitutions.items():
        content = content.replace(key, value)

    self.mock_files[str(path)] = content

def _rctx_which(self, program):
    prog_str = str(program)
    if prog_str in self.mock_which:
        res = self.mock_which[prog_str]
        if res == None:
            return None
        return _path_new(res, self.mock_files)
    return None

def _rctx_download(
        self,
        url,
        output = "",
        sha256 = "",
        executable = False,
        allow_fail = False,
        canonical_id = "",
        auth = {},
        headers = {},
        integrity = ""):
    _ = (
        sha256,
        executable,
        allow_fail,
        canonical_id,
        auth,
        headers,
        integrity,
    )  # @unused

    urls = url if type(url) == "list" else [url]

    for u in urls:
        if u in self.mock_downloads:
            res = self.mock_downloads[u]
            if type(res) == "string":
                out = _get_download_file_name(u, output)
                self.mock_files[out] = res
                return struct(success = True, sha256 = "mocksha256")
            else:
                return res(
                    self,
                    u,
                    output,
                    sha256,
                    executable,
                    allow_fail,
                    canonical_id,
                    auth,
                    headers,
                    integrity,
                )

    if not allow_fail:
        fail("Download not mocked for url: " + str(urls))
    return struct(success = False)

def _rctx_extract(
        self,
        archive,
        output = "",
        stripPrefix = "",
        rename_files = {},
        *,
        watch_archive = "auto"):
    _ = (
        stripPrefix,
        rename_files,
        watch_archive,
    )  # @unused

    archive_str = str(archive)
    if archive_str in self.mock_extracts:
        for f, c in self.mock_extracts[archive_str].items():
            out_path = "{}/{}".format(output, f) if output else str(f)
            self.mock_files[out_path] = c

def _rctx_download_and_extract(
        self,
        url,
        output = "",
        sha256 = "",
        type = "",
        stripPrefix = "",
        allow_fail = False,
        canonical_id = "",
        auth = {},
        headers = {},
        integrity = "",
        rename_files = {}):
    _ = type  # @unused

    res = self.download(
        url = url,
        output = "",
        sha256 = sha256,
        allow_fail = allow_fail,
        canonical_id = canonical_id,
        auth = auth,
        headers = headers,
        integrity = integrity,
    )
    if not res.success:
        return res

    urls = url if type(url) == "list" else [url]
    for u in urls:
        downloaded_file = _get_download_file_name(u)
        if downloaded_file in self.mock_extracts:
            self.extract(
                archive = downloaded_file,
                output = output,
                stripPrefix = stripPrefix,
                rename_files = rename_files,
            )
            break

    return res

def _rctx_execute(
        self,
        arguments,
        timeout = 600,
        quiet = True,
        working_directory = "",
        environment = {},
        custom_reporter = ""):
    _ = (
        self,
        arguments,
        timeout,
        quiet,
        working_directory,
        environment,
        custom_reporter,
    )  # @unused
    return struct(return_code = 0, stdout = "", stderr = "")

def _rctx_symlink(self, target, link_name):
    self.mock_files[str(link_name)] = {"target": str(target), "type": "symlink"}

def _rctx_new(
        attr = None,
        environ = None,
        mock_files = None,
        mock_which = None,
        mock_downloads = None,
        mock_extracts = None,
        os_name = "linux",
        arch_name = "x86_64"):
    """Create a mock repository_ctx object.

    Args:
        attr: {type}`dict` Dict of attributes.
        environ: {type}`dict[string, string]` Dict of environment variables.
        mock_files: {type}`dict[string, string]` Dict mapping path strings
            to content.
        mock_which: {type}`dict[string, string]` Dict mapping program
            name to path string.
        mock_downloads: {type}`dict[string, string|callable]` Dict mapping
            url to string or callable.
        mock_extracts: {type}`dict[string, dict[string, string]]` Dict mapping
            downloaded filename to a dict of extracted filename to content.
        os_name: {type}`string` The OS name.
        arch_name: {type}`string` The architecture name.

    Returns:
        {type}`MockRepositoryCtx` A struct mocking a repository_ctx object.
    """
    attr = attr or {}
    environ = environ or {}
    mock_files = mock_files or {}
    mock_which = mock_which or {}
    mock_downloads = mock_downloads or {}
    mock_extracts = mock_extracts or {}

    # buildifier: disable=uninitialized
    self = struct(
        mock_files = mock_files,
        mock_which = mock_which,
        mock_downloads = mock_downloads,
        mock_extracts = mock_extracts,
        attr = struct(**attr),
        os = struct(
            name = os_name,
            arch = arch_name,
        ),
        os_environ = environ,
        path = lambda *a, **k: _rctx_path(self, *a, **k),
        read = lambda *a, **k: _rctx_read(self, *a, **k),
        file = lambda *a, **k: _rctx_file(self, *a, **k),
        template = lambda *a, **k: _rctx_template(self, *a, **k),
        which = lambda *a, **k: _rctx_which(self, *a, **k),
        download = lambda *a, **k: _rctx_download(self, *a, **k),
        extract = lambda *a, **k: _rctx_extract(self, *a, **k),
        download_and_extract = lambda *a, **k: _rctx_download_and_extract(
            self,
            *a,
            **k
        ),
        execute = lambda *a, **k: _rctx_execute(self, *a, **k),
        symlink = lambda *a, **k: _rctx_symlink(self, *a, **k),
    )

    return self

def _glob_call_new(*args, **kwargs):
    """Create a struct representing a glob call.

    Args:
        *args: {type}`tuple` Positional arguments to glob.
        **kwargs: {type}`dict` Keyword arguments to glob.

    Returns:
        {type}`MockGlobCall` A struct with glob and kwargs fields.
    """
    return struct(
        glob = args,
        kwargs = kwargs,
    )

def _glob_new():
    """Create a mock glob object.

    Returns:
        {type}`MockGlob` A struct with calls and results lists, and a
            glob function.
    """
    calls = []
    results = []

    def _glob_fn(*args, **kwargs):
        calls.append(_glob_call_new(*args, **kwargs))
        if not results:
            fail("Mock glob missing for invocation: args={} kwargs={}".format(
                args,
                kwargs,
            ))
        return results.pop(0)

    return struct(
        calls = calls,
        results = results,
        glob = _glob_fn,
    )

def _select_new(value, no_match_error = None):
    """A mock select function that returns the value.

    Args:
        value: {type}`Any` The value to return.
        no_match_error: {type}`string` Ignored.

    Returns:
        {type}`MockSelect` The value.
    """
    _ = no_match_error  # @unused
    return value

mocks = struct(
    file = _file_new,
    glob = _glob_new,
    glob_call = _glob_call_new,
    mctx = _mctx_new,
    module = _module_new,
    path = _path_new,
    rctx = _rctx_new,
    select = _select_new,
    tag = _tag_new,
)

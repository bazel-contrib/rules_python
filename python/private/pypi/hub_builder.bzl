"""A hub repository builder for incrementally building the hub configuration."""

load("//python/private:full_version.bzl", "full_version")
load("//python/private:normalize_name.bzl", "normalize_name")
load("//python/private:version.bzl", "version")
load("//python/private:version_label.bzl", "version_label")
load(":pep508_env.bzl", "env")
load(":pep508_evaluate.bzl", "evaluate")
load(":python_tag.bzl", "python_tag")

def hub_builder(
        *,
        name,
        module_name,
        config,
        minor_mapping,
        available_interpreters,
        simpleapi_download_fn,
        simpleapi_cache = {}):
    """Return a hub builder instance

    Args:
        name: TODO
        module_name: TODO
        config: The platform configuration.
        minor_mapping: TODO
        available_interpreters: {type}`dict[str, Label]` The dictionary of available
            interpreters that have been registered using the `python` bzlmod extension.
            The keys are in the form `python_{snake_case_version}_host`. This is to be
            used during the `repository_rule` and must be always compatible with the host.
        simpleapi_download_fn: TODO
        simpleapi_cache: TODO
    """

    # buildifier: disable=uninitialized
    self = struct(
        name = name,
        module_name = module_name,
        python_versions = {},
        config = config,
        whl_map = {},
        exposed_packages = {},
        extra_aliases = {},
        whl_libraries = {},
        _minor_mapping = minor_mapping,
        _available_interpreters = available_interpreters,
        _simpleapi_download_fn = simpleapi_download_fn,
        _simpleapi_cache = simpleapi_cache,
        _get_index_urls = {},
        # keep sorted
        add = lambda *a, **k: _add(self, *a, **k),
        detect_interpreter = lambda *a, **k: _detect_interpreter(self, *a, **k),
        get_index_urls = lambda version: self._get_index_urls[version],
        platforms = lambda version: self.python_versions[version],
        add_whl_library = lambda *a, **k: _add_whl_library(self, *a, **k),
    )

    # buildifier: enable=uninitialized
    return self

def _add(self, *, pip_attr):
    python_version = pip_attr.python_version
    if python_version in self.python_versions:
        fail((
            "Duplicate pip python version '{version}' for hub " +
            "'{hub}' in module '{module}': the Python versions " +
            "used for a hub must be unique"
        ).format(
            hub = self.name,
            module = self.module_name,
            version = python_version,
        ))

    self.python_versions[python_version] = _platforms(
        python_version = python_version,
        minor_mapping = self._minor_mapping,
        config = self.config,
    )
    self._get_index_urls[python_version] = _get_index_urls(self, pip_attr)

def _get_index_urls(self, pip_attr):
    if not pip_attr.experimental_index_url:
        if pip_attr.experimental_extra_index_urls:
            fail("'experimental_extra_index_urls' is a no-op unless 'experimental_index_url' is set")
        elif pip_attr.experimental_index_url_overrides:
            fail("'experimental_index_url_overrides' is a no-op unless 'experimental_index_url' is set")

        return None

    skip_sources = [
        normalize_name(s)
        for s in pip_attr.simpleapi_skip
    ]
    return lambda ctx, distributions: self._simpleapi_download_fn(
        ctx,
        attr = struct(
            index_url = pip_attr.experimental_index_url,
            extra_index_urls = pip_attr.experimental_extra_index_urls or [],
            index_url_overrides = pip_attr.experimental_index_url_overrides or {},
            sources = [
                d
                for d in distributions
                if normalize_name(d) not in skip_sources
            ],
            envsubst = pip_attr.envsubst,
            # Auth related info
            netrc = pip_attr.netrc,
            auth_patterns = pip_attr.auth_patterns,
        ),
        cache = self._simpleapi_cache,
        parallel_download = pip_attr.parallel_download,
    )

def _detect_interpreter(self, pip_attr):
    python_interpreter_target = pip_attr.python_interpreter_target
    if python_interpreter_target == None and not pip_attr.python_interpreter:
        python_name = "python_{}_host".format(
            pip_attr.python_version.replace(".", "_"),
        )
        if python_name not in self._available_interpreters:
            fail((
                "Unable to find interpreter for pip hub '{hub_name}' for " +
                "python_version={version}: Make sure a corresponding " +
                '`python.toolchain(python_version="{version}")` call exists.' +
                "Expected to find {python_name} among registered versions:\n  {labels}"
            ).format(
                hub_name = self.name,
                version = pip_attr.python_version,
                python_name = python_name,
                labels = "  \n".join(self._available_interpreters),
            ))
        python_interpreter_target = self._available_interpreters[python_name]

    return struct(
        target = python_interpreter_target,
        path = pip_attr.python_interpreter,
    )

def _platforms(*, python_version, minor_mapping, config):
    platforms = {}
    python_version = version.parse(
        full_version(
            version = python_version,
            minor_mapping = minor_mapping,
        ),
        strict = True,
    )

    for platform, values in config.platforms.items():
        # TODO @aignas 2025-07-07: this is probably doing the parsing of the version too
        # many times.
        abi = "{}{}{}.{}".format(
            python_tag(values.env["implementation_name"]),
            python_version.release[0],
            python_version.release[1],
            python_version.release[2],
        )
        key = "{}_{}".format(abi, platform)

        env_ = env(
            env = values.env,
            os = values.os_name,
            arch = values.arch_name,
            python_version = python_version.string,
        )

        if values.marker and not evaluate(values.marker, env = env_):
            continue

        platforms[key] = struct(
            env = env_,
            triple = "{}_{}_{}".format(abi, values.os_name, values.arch_name),
            whl_abi_tags = [
                v.format(
                    major = python_version.release[0],
                    minor = python_version.release[1],
                )
                for v in values.whl_abi_tags
            ],
            whl_platform_tags = values.whl_platform_tags,
        )
    return platforms

def _add_whl_library(self, *, python_version, whl, repo):
    if repo == None:
        # NOTE @aignas 2025-07-07: we guard against an edge-case where there
        # are more platforms defined than there are wheels for and users
        # disallow building from sdist.
        return

    platforms = self.python_versions[python_version]

    # TODO @aignas 2025-06-29: we should not need the version in the repo_name if
    # we are using pipstar and we are downloading the wheel using the downloader
    repo_name = "{}_{}_{}".format(self.name, version_label(python_version), repo.repo_name)

    if repo_name in self.whl_libraries:
        fail("attempting to create a duplicate library {} for {}".format(
            repo_name,
            whl.name,
        ))
    self.whl_libraries[repo_name] = repo.args

    if not self.config.enable_pipstar and "experimental_target_platforms" in repo.args:
        self.whl_libraries[repo_name] |= {
            "experimental_target_platforms": sorted({
                # TODO @aignas 2025-07-07: this should be solved in a better way
                platforms[candidate].triple.partition("_")[-1]: None
                for p in repo.args["experimental_target_platforms"]
                for candidate in platforms
                if candidate.endswith(p)
            }),
        }

    mapping = self.whl_map.setdefault(whl.name, {})
    if repo.config_setting in mapping and mapping[repo.config_setting] != repo_name:
        fail(
            "attempting to override an existing repo '{}' for config setting '{}' with a new repo '{}'".format(
                mapping[repo.config_setting],
                repo.config_setting,
                repo_name,
            ),
        )
    else:
        mapping[repo.config_setting] = repo_name

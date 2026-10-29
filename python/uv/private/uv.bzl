# Copyright 2024 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""A module extension for working with uv."""

load("//python/private:auth.bzl", "AUTH_ATTRS", "get_auth")
load(":dist_manifest.bzl", "DEFAULT_MANIFEST_FILENAME", "dist_manifest_resolver")
load(":toolchain_types.bzl", "UV_TOOLCHAIN_TYPE")
load(":uv_repository.bzl", "uv_repository")
load(":uv_toolchain_config.bzl", "apply_configure", "define_toolchains", "set_config")
load(":uv_toolchains_repo.bzl", "uv_toolchains_repo")

_DOC = """\
A module extension for working with uv.

Basic usage:
```starlark
uv = use_extension(
    "@rules_python//python/uv:uv.bzl",
    "uv",
    # Use `dev_dependency` so that the toolchains are not defined pulled when
    # your module is used elsewhere.
    dev_dependency = True,
)
uv.configure(version = "0.13.5")
```

Since this is only for locking the requirements files, it should be always
marked as a `dev_dependency`.
"""

_DEFAULT_ATTRS = {
    "base_url": attr.string(
        doc = """\
Base URL to download metadata about the binaries and the binaries themselves.
""",
    ),
    "compatible_with": attr.label_list(
        doc = """\
The compatible with constraint values for toolchain resolution.
""",
    ),
    "manifest_filename": attr.string(
        doc = """\
The distribution manifest filename to use for the metadata fetching from GH. The
defaults for this are set in `rules_python` MODULE.bazel file that one can override
for a specific version.
""",
        default = DEFAULT_MANIFEST_FILENAME,
    ),
    "platform": attr.string(
        doc = """\
The platform string used in the UV repository to denote the platform triple.
""",
    ),
    "target_settings": attr.label_list(
        doc = """\
The `target_settings` to add to platform definitions that then get used in `toolchain`
definitions.
""",
    ),
    "version": attr.string(
        doc = """\
The version of uv to configure the sources for. If this is not specified it will be the
last version used in the module or the default version set by `rules_python`.
""",
    ),
} | AUTH_ATTRS

default = tag_class(
    doc = """
Set the uv configuration defaults.

:::{versionchanged} VERSION_NEXT_PATCH
`netrc` and `auth_patterns` now apply to the versions configured with
{obj}`uv.configure`; previously they were accepted but ignored.
:::
""",
    attrs = _DEFAULT_ATTRS,
)

configure = tag_class(
    doc = """\
Build the `uv` toolchain configuration by appending the provided configuration.
The information is appended to the version configuration that is specified by
{attr}`version` attribute, or if the version is unspecified, the version of the
last {obj}`uv.configure` call in the current module, or the version from the
defaults is used.

Complex configuration example:
```starlark
# Configure the base_url for the default version.
uv.configure(base_url = "my_mirror")

# Add an extra platform that can be used with your version.
uv.configure(
    platform = "extra-platform",
    target_settings = ["//my_config_setting_label"],
    compatible_with = ["@platforms//os:exotic"],
)

# Add an extra platform that can be used with your version.
uv.configure(
    platform = "patched-binary",
    target_settings = ["//my_super_config_setting"],
    urls = ["https://example.zip"],
    sha256 = "deadbeef",
)
```
""",
    attrs = _DEFAULT_ATTRS | {
        "sha256": attr.string(
            doc = "The sha256 of the downloaded artifact if the {attr}`urls` is specified.",
        ),
        "urls": attr.string_list(
            doc = """\
The urls to download the binary from. If this is used, {attr}`base_url` and
{attr}`manifest_filename` are ignored for the given version.

::::note
If the `urls` are specified, they need to be specified for all of the platforms
for a particular version.
::::
""",
        ),
    },
)

def process_modules(
        module_ctx,
        hub_name = "uv",
        uv_repository = uv_repository,
        toolchain_type = str(UV_TOOLCHAIN_TYPE),
        hub_repo = uv_toolchains_repo,
        get_auth = get_auth):
    """Parse the modules to get the config for 'uv' toolchains.

    Args:
        module_ctx: the context.
        hub_name: the name of the hub repository.
        uv_repository: the rule to create a uv_repository override.
        toolchain_type: the toolchain type to use here.
        hub_repo: the hub repo factory function to use.
        get_auth: the auth function to use.

    Returns:
        the result of the hub_repo. Mainly used for tests.
    """

    # default values to apply for version specific config
    defaults = {
        "base_url": "",
        "manifest_filename": "",
        "platforms": {
            # The structure is as follows:
            # "platform_name": struct(
            #     compatible_with = [],
            #     target_settings = [],
            # ),
            #
            # NOTE: urls and sha256 cannot be set in defaults
        },
        "version": "",
    }
    for mod in module_ctx.modules:
        if not (mod.is_root or mod.name == "rules_python"):
            continue

        for tag in mod.tags.default:
            set_config(
                defaults,
                version = tag.version,
                base_url = tag.base_url,
                manifest_filename = tag.manifest_filename,
                platform = tag.platform,
                compatible_with = tag.compatible_with,
                target_settings = tag.target_settings,
                override = mod.is_root,
                netrc = tag.netrc,
                auth_patterns = tag.auth_patterns,
            )

    for key in [
        "version",
        "manifest_filename",
        "platforms",
    ]:
        if not defaults.get(key, None):
            fail("defaults need to be set for '{}'".format(key))

    # resolved per-version configuration; see `apply_configure`.
    versions = {}
    for mod in module_ctx.modules:
        if not (mod.is_root or mod.name == "rules_python"):
            continue

        apply_configure(
            versions,
            mod.tags.configure,
            defaults = defaults,
            override = mod.is_root,
        )

    return define_toolchains(
        hub_name = hub_name,
        versions = versions,
        uv_repository = uv_repository,
        hub_repo = hub_repo,
        toolchain_type = toolchain_type,
        resolve_sources = dist_manifest_resolver(module_ctx, get_auth = get_auth),
    )

def _uv_toolchain_extension(module_ctx):
    process_modules(
        module_ctx,
        hub_name = "uv",
    )

uv = module_extension(
    doc = _DOC,
    implementation = _uv_toolchain_extension,
    tag_classes = {
        "configure": configure,
        "default": default,
    },
)

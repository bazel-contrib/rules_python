"""Print the toolchain versions.
"""

load("//python:versions.bzl", "TOOL_VERSIONS", "get_release_info")
load("//python/private:text_util.bzl", "render")
load("//python/private:version.bzl", "version")

def print_toolchains_checksums(name):
    """A macro to print checksums for a particular Python interpreter version.

    Args:
        name: {type}`str`: the name of the runnable target.
    """
    by_version = {}

    for python_version, metadata in TOOL_VERSIONS.items():
        by_version[python_version] = _commands_for_version(
            python_version = python_version,
            metadata = metadata,
        )

    all_commands = sorted(
        by_version.items(),
        key = lambda x: version.key(version.parse(x[0], strict = True)),
    )
    all_commands = [x[1] for x in all_commands]

    template = """\
cat > "$@" <<'EOF'
#!/bin/bash

set -o errexit -o nounset -o pipefail

echo "Fetching hashes..."

{commands}
EOF
    """

    native.genrule(
        name = name,
        srcs = [],
        outs = ["print_toolchains_checksums.sh"],
        cmd = select({
            "//python/config_settings:is_python_{}".format(version_str): template.format(
                commands = commands,
            )
            for version_str, commands in by_version.items()
        } | {
            "//conditions:default": template.format(commands = "\n".join(all_commands)),
        }),
        executable = True,
    )

def _commands_for_version(*, python_version, metadata):
    lines = []
    lines += [
        "cat <<EOB",  # end of block
        "    \"{python_version}\": {{".format(python_version = python_version),
        "        \"url\": \"{url}\",".format(url = metadata["url"]),
        "        \"sha256\": {",
    ]

    for platform in metadata["sha256"].keys():
        for release_url in get_release_info(platform, python_version)[1]:
            # Do lines one by one so that the progress is seen better and use cat for ease of quotation
            lines += [
                "EOB",
                "cat <<EOB",
                "            \"{platform}\": \"$$({get_sha256})\",".format(
                    platform = platform,
                    get_sha256 = "curl --silent --show-error --location --fail {release_url_sha256}".format(
                        release_url = release_url,
                        release_url_sha256 = release_url + ".sha256",
                    ),
                ),
            ]

    prefix = metadata["strip_prefix"]
    prefix = render.indent(
        render.dict(prefix) if type(prefix) == type({}) else repr(prefix),
        indent = " " * 8,
    ).lstrip()

    lines += [
        "        },",
        "        \"strip_prefix\": {strip_prefix},".format(strip_prefix = prefix),
        "    },",
        "EOB",
    ]

    return "\n".join(lines)

"""The workloads that are measured by the benchmarks and the steps test."""

load("//python/private:version.bzl", "version")  # buildifier: disable=bzl-visibility
load("//python/private/pypi:pep508_evaluate.bzl", "evaluate", "parse", "tokenize")  # buildifier: disable=bzl-visibility

_ENV = {
    "extra": "foo",
    "implementation_name": "cpython",
    "implementation_version": "3.11.4",
    "os_name": "posix",
    "platform_machine": "x86_64",
    "platform_python_implementation": "CPython",
    "platform_release": "6.1.0",
    "platform_system": "Linux",
    "platform_version": "#1 SMP Debian",
    "python_full_version": "3.11.4",
    "python_version": "3.11",
    "sys_platform": "linux",
}

# This is what the universal lock files have for the packages that are only
# built for some of the platforms.
_LONG_MARKER = (
    "(python_full_version >= '3.12' and platform_machine == 'aarch64' and sys_platform == 'linux')" +
    " or (python_full_version >= '3.12' and platform_machine == 'x86_64' and sys_platform == 'linux')" +
    " or (python_full_version < '3.12' and platform_machine != 'aarch64'" +
    " and platform_machine != 'x86_64' and sys_platform == 'linux')" +
    " or sys_platform == 'darwin' or sys_platform == 'win32'"
)
_PARSED_LONG_MARKER = parse(_LONG_MARKER)
_PARSED_VERSION_MARKER = parse("python_version >= '3.8'")

_V_3_8 = version.parse("3.8")
_V_3_11_4 = version.parse("3.11.4")
_V_3_11_PREFIX = version.parse("3.11.*")

WORKLOADS = {
    # keep sorted
    "evaluate_long": lambda: evaluate(_LONG_MARKER, env = _ENV),
    "evaluate_long_parsed": lambda: evaluate(_PARSED_LONG_MARKER, env = _ENV),
    "evaluate_non_strict": lambda: evaluate(
        "python_version < '3.11' and extra == 'dev'",
        env = {"extra": "dev"},
        strict = False,
    ),
    "evaluate_string": lambda: evaluate("sys_platform == 'win32'", env = _ENV),
    "evaluate_two_strings": lambda: evaluate("os_name == 'posix' and sys_platform == 'linux'", env = _ENV),
    "evaluate_version": lambda: evaluate("python_version >= '3.8'", env = _ENV),
    "evaluate_version_parsed": lambda: evaluate(_PARSED_VERSION_MARKER, env = _ENV),
    "parse_long": lambda: parse(_LONG_MARKER),
    "tokenize_long": lambda: tokenize(_LONG_MARKER),
    "tokenize_no_whitespace": lambda: tokenize("python_version>='3.8' and os_name=='posix'"),
    "tokenize_version": lambda: tokenize("python_version >= '3.8'"),
    "version_is_compatible": lambda: version.is_compatible(_V_3_11_4, _V_3_8),
    "version_is_eq_prefix": lambda: version.is_eq(_V_3_11_4, _V_3_11_PREFIX),
    "version_is_ge": lambda: version.is_ge(_V_3_11_4, _V_3_8),
    "version_is_lt": lambda: version.is_lt(_V_3_11_4, _V_3_8),
    "version_key": lambda: version.key(_V_3_11_4),
    "version_normalize": lambda: version.normalize("2023.07.19"),
    "version_parse_all_segments": lambda: version.parse("1!2.0.0rc1.post3.dev4+ubuntu.7"),
    "version_parse_invalid": lambda: version.parse("#1 SMP Debian"),
    "version_parse_pre_release": lambda: version.parse("3.13.0rc1"),
    "version_parse_prefix": lambda: version.parse("3.11.*"),
    "version_parse_release": lambda: version.parse("3.11.4"),
}

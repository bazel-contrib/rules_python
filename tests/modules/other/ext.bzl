"""Module extension declared by 'other' module for testing __init__.py generation."""

_BUILD_FILE_CONTENT = """\
load("@rules_python//tests/support:explicit_init_py_test.bzl", "explicit_init_py_test")

explicit_init_py_test(
    name = "test",
    main = "main.py",
    expect_generated_init = False,
)
"""

_MAIN_PY_CONTENT = "print('hello, world')"

def _repo_impl(ctx):
    ctx.file("main.py", _MAIN_PY_CONTENT)
    ctx.file("BUILD.bazel", _BUILD_FILE_CONTENT)

init_py_test_repo = repository_rule(implementation = _repo_impl)

def _other_init_py_test_ext_impl(module_ctx):
    for mod in module_ctx.modules:
        for tag in mod.tags.repo:
            init_py_test_repo(name = tag.name)

_repo_tag = tag_class(
    attrs = {
        "name": attr.string(mandatory = True),
    },
)

other_init_py_test_ext = module_extension(
    implementation = _other_init_py_test_ext_impl,
    tag_classes = {
        "repo": _repo_tag,
    },
)

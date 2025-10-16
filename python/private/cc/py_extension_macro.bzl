"""Wrapper macro for the py_extension rule."""

load("@rules_cc//cc:cc_shared_library.bzl", "cc_shared_library")
load("//python/private:util.bzl", "add_tag")
load(
    ":py_extension_rule.bzl",
    _py_extension = "py_extension",
    ##_py_extension_csl_rule = "py_extension_csl",
)

def py_extension(**kwargs):
    """A macro that calls the py_extension rule and adds a tag.

    Args:
        **kwargs: Additional arguments to pass to the rule.
    """
    add_tag(kwargs, "@rules_python//python/cc:py_extension")

    use_csl = kwargs.pop("use_csl", False)
    if use_csl:
        _py_extension_csl(**kwargs)
    else:
        _py_extension(**kwargs)

def _py_extension_csl(*, name, module_name = None, **kwargs):
    if not module_name:
        module_name = name

    cc_shared_library(
        name = name,
        shared_lib_name = module_name + ".so",
        **kwargs
    )

"""Wrapper macro for the py_extension rule."""

load("//python/private:util.bzl", "add_tag")
load(":py_extension_rule.bzl", _py_extension = "py_extension")

def py_extension(**kwargs):
    """A macro that calls the py_extension rule and adds a tag.

    Args:
        **kwargs: Additional arguments to pass to the rule.
    """
    add_tag(kwargs, "@rules_python//python/cc:py_extension")
    _py_extension(**kwargs)

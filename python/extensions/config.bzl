"""Extension for configuring global settings of rules_python."""

load("//python/private:internal_config_repo.bzl", "internal_config_repo")
load("//python/private/pypi:deps.bzl", "pypi_deps")

_add_transition_setting = tag_class(
    doc = """
Specify a build setting that terminal rules transition on by default.

Terminal rules are rules such as py_binary, py_test, py_wheel, or similar
rules that represent some deployable unit. Settings added here can
then be used a keys with the {obj}`config_settings` attribute.

:::{note}
This adds the label as a dependency of the Python rules. Take care to not refer
to repositories that are expensive to create or invalidate frequently.
:::
""",
    attrs = {
        "setting": attr.label(doc = "The build setting to add."),
    },
)

def _config_impl(mctx):
    transition_setting_generators = {}
    transition_settings = []
    for mod in mctx.modules:
        for tag in mod.tags.add_transition_setting:
            setting = str(tag.setting)
            if setting not in transition_setting_generators:
                transition_setting_generators[setting] = []
                transition_settings.append(setting)
            transition_setting_generators[setting].append(mod.name)

    internal_config_repo(
        name = "rules_python_internal",
        transition_setting_generators = transition_setting_generators,
        transition_settings = transition_settings,
    )

    pypi_deps()

config = module_extension(
    doc = """Global settings for rules_python.

:::{versionadded} VERSION_NEXT_FEATURE
:::
""",
    implementation = _config_impl,
    tag_classes = {
        "add_transition_setting": _add_transition_setting,
    },
)

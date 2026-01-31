load("@bazel_skylib//lib:selects.bzl", "selects")
load("//python/private/pypi:env_marker_setting.bzl", "env_marker_setting")
load("//python/private/pypi:wheel_tags_setting.bzl", "wheel_tags_setting")

def gen_package_config_settings(name, config_settings, marker, wheel_tags):
    match_all = list(config_settings)
    wt_name = name + "_wheeltags"
    wheel_tags_setting(
        name = wt_name,
        **wheel_tags
    )
    match_all.append("is_{}_true".format(wt_name))
    if marker:
        em_name = name + "_marker"
        env_marker_setting(
            name = em_name,
            expression = marker,
        )
        match_all("is_{}_true".format(em_name))

    selects.config_setting_group(
        name = name,
        match_all = match_all,
    )

def define_targets(name, selectors):
    select_map = {}
    for i, selector in enumerate(selectors):
        actual_repo = selector["actual_repo"]
        actual = "@{}//:output.zip".format(actual_repo)
        condition_name = "pick_{}_{}".format(i, actual_repo)
        gen_package_config_settings(
            name = condition_name,
            config_settings = selector["config_settings"],
            marker = selector["marker"],
            wheel_tags = selector["wheel_tags"],
        )
        select_map[condition_name] = actual

    native.alias(
        name = name,
        actual = select(select_map),
    )

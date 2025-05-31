# Configuration file for the Sphinx documentation builder.
#
# For the full list of built-in configuration values, see the documentation:
# https://www.sphinx-doc.org/en/master/usage/configuration.html

# -- Project info

project = "Sphinx Docs Test xx"

extensions = [
    "myst_parser",
]
myst_enable_extensions = [
    "colon_fence",
]

import logging
logger = logging.getLogger('conf')

def on_env_get_outdated(*args, **kwargs):
    logger.info("env-get-outdated args: %s", args)
    logger.info("env-get-outdated kwargs: %s", kwargs)
    return []


def setup(app):

    app.connect('env-get-outdated', on_env_get_outdated)

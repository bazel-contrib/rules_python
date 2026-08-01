import os
import re
import unittest
from pathlib import Path


class TestContents(unittest.TestCase):
    maxDiff = None

    @staticmethod
    def _get_files(env_var: str) -> list[str]:
        return [
            f.partition("site-packages/")[-1] for f in os.environ[env_var].split(" ")
        ]

    def test_sdist_srcs(self):
        self.assertEqual(
            self._get_files("SDIST_SRC_FILES"),
            [
                "requests/__init__.py",
                "requests/__version__.py",
                "requests/_internal_utils.py",
                "requests/_types.py",
                "requests/adapters.py",
                "requests/api.py",
                "requests/auth.py",
                "requests/certs.py",
                "requests/compat.py",
                "requests/cookies.py",
                "requests/exceptions.py",
                "requests/help.py",
                "requests/hooks.py",
                "requests/models.py",
                "requests/packages.py",
                "requests/sessions.py",
                "requests/status_codes.py",
                "requests/structures.py",
                "requests/utils.py",
            ],
        )

    def test_srcs(self):
        self.assertEqual(
            self._get_files("SRC_FILES"),
            [
                "requests/__init__.py",
                "requests/__version__.py",
                "requests/_internal_utils.py",
                "requests/_types.py",
                "requests/adapters.py",
                "requests/api.py",
                "requests/auth.py",
                "requests/certs.py",
                "requests/compat.py",
                "requests/cookies.py",
                "requests/exceptions.py",
                "requests/help.py",
                "requests/hooks.py",
                "requests/models.py",
                "requests/packages.py",
                "requests/sessions.py",
                "requests/status_codes.py",
                "requests/structures.py",
                "requests/utils.py",
            ],
        )

    def test_whl_srcs(self):
        self.assertEqual(
            self._get_files("WHL_FILES"),
            [
                "requests/__init__.py",
                "requests/__version__.py",
                "requests/_internal_utils.py",
                "requests/_types.py",
                "requests/adapters.py",
                "requests/api.py",
                "requests/auth.py",
                "requests/certs.py",
                "requests/compat.py",
                "requests/cookies.py",
                "requests/exceptions.py",
                "requests/help.py",
                "requests/hooks.py",
                "requests/models.py",
                "requests/packages.py",
                "requests/sessions.py",
                "requests/status_codes.py",
                "requests/structures.py",
                "requests/utils.py",
            ],
        )

    def test_whl_location(self):
        self.assertTrue(
            os.environ["WHL_LOCATION"].endswith("requests-2.34.2-py3-none-any.whl"),
            msg=os.environ["WHL_LOCATION"],
        )
        self.assertTrue(
            os.environ["WHL_DEPS_LOCATION"].endswith(
                "requests-2.34.2-py3-none-any.whl"
            ),
            msg=os.environ["WHL_DEPS_LOCATION"],
        )

    @staticmethod
    def _read_file(env_var: str) -> list[str]:
        return set(Path(os.environ[env_var]).read_text().splitlines())

    @staticmethod
    def _normalize_label(label: str) -> str:
        if not label.startswith("@@"):
            return label
        repo, _, rest = label.partition("//")
        parts = [p for p in re.split(r"[~+]", repo[2:]) if p]
        if parts:
            return f"@{parts[-1]}//{rest}"
        return label

    def test_whl_deps_ar_the_same(self):
        for var, main_dep in {
            "WHL_DEPS": "@whl_archive//:pkg",
            "WHL_TARGET_DEPS": "@whl_deps_library//:pkg",
        }.items():
            self.assertEqual(
                {
                    self._normalize_label(x)
                    for x in self._read_file(var)
                    if not x.endswith("toolchain_type")
                },
                {
                    main_dep,
                    "//:certifi_pkg",
                    "//:charset_normalizer_pkg",
                    "//:idna_pkg",
                    "//:urllib3_pkg",
                    "@whl_archive//:data",
                    "@whl_archive//:package_metadata",
                    "@whl_archive//:site-packages/requests-2.34.2.dist-info/INSTALLER",
                    "@whl_archive//:site-packages/requests-2.34.2.dist-info/METADATA",
                    "@whl_archive//:site-packages/requests-2.34.2.dist-info/RECORD",
                    "@whl_archive//:site-packages/requests-2.34.2.dist-info/WHEEL",
                    "@whl_archive//:site-packages/requests-2.34.2.dist-info/licenses/LICENSE",
                    "@whl_archive//:site-packages/requests-2.34.2.dist-info/licenses/NOTICE",
                    "@whl_archive//:site-packages/requests-2.34.2.dist-info/top_level.txt",
                    "@whl_archive//:site-packages/requests/__init__.py",
                    "@whl_archive//:site-packages/requests/__version__.py",
                    "@whl_archive//:site-packages/requests/_internal_utils.py",
                    "@whl_archive//:site-packages/requests/_types.py",
                    "@whl_archive//:site-packages/requests/adapters.py",
                    "@whl_archive//:site-packages/requests/api.py",
                    "@whl_archive//:site-packages/requests/auth.py",
                    "@whl_archive//:site-packages/requests/certs.py",
                    "@whl_archive//:site-packages/requests/compat.py",
                    "@whl_archive//:site-packages/requests/cookies.py",
                    "@whl_archive//:site-packages/requests/exceptions.py",
                    "@whl_archive//:site-packages/requests/help.py",
                    "@whl_archive//:site-packages/requests/hooks.py",
                    "@whl_archive//:site-packages/requests/models.py",
                    "@whl_archive//:site-packages/requests/packages.py",
                    "@whl_archive//:site-packages/requests/py.typed",
                    "@whl_archive//:site-packages/requests/sessions.py",
                    "@whl_archive//:site-packages/requests/status_codes.py",
                    "@whl_archive//:site-packages/requests/structures.py",
                    "@whl_archive//:site-packages/requests/utils.py",
                    "@whl_archive//:srcs",
                    "@rules_python//python:none",
                    "@rules_python//python/config_settings:_is_venvs_site_packages_yes",
                    "@rules_python//python/config_settings:add_srcs_to_runfiles",
                    "@rules_python//python/config_settings:precompile",
                    "@rules_python//python/config_settings:precompile_source_retention",
                    "@rules_python//python/config_settings:venvs_site_packages",
                    "@rules_python//python/private:sentinel",
                },
            )


if __name__ == "__main__":
    unittest.main()

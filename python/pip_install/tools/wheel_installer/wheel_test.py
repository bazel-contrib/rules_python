import unittest
from random import shuffle

from python.pip_install.tools.wheel_installer import wheel


class DepsTest(unittest.TestCase):
    def test_simple(self):
        deps = wheel.Deps("foo", requires_dist=["bar"])

        got = deps.build()

        self.assertIsInstance(got, wheel.FrozenDeps)
        self.assertEqual(["bar"], got.deps)
        self.assertEqual({}, got.deps_select)

    def test_can_add_os_specific_deps(self):
        platforms = {
            "linux_x86_64",
            "osx_x86_64",
            "osx_aarch64",
            "windows_x86_64",
        }
        deps = wheel.Deps(
            "foo",
            requires_dist=[
                "bar",
                "an_osx_dep; sys_platform=='darwin'",
                "posix_dep; os_name=='posix'",
                "win_dep; os_name=='nt'",
            ],
            platforms=set(wheel.Platform.from_string(platforms)),
        )

        got = deps.build()

        self.assertEqual(["bar"], got.deps)
        self.assertEqual(
            {
                "@platforms//os:linux": ["posix_dep"],
                "@platforms//os:osx": ["an_osx_dep", "posix_dep"],
                "@platforms//os:windows": ["win_dep"],
            },
            got.deps_select,
        )

    def test_deps_are_added_to_more_specialized_platforms(self):
        platforms = {
            "osx_x86_64",
            "osx_aarch64",
        }
        got = wheel.Deps(
            "foo",
            requires_dist=[
                "m1_dep; sys_platform=='darwin' and platform_machine=='arm64'",
                "mac_dep; sys_platform=='darwin'",
            ],
            platforms=set(wheel.Platform.from_string(platforms)),
        ).build()

        self.assertEqual(
            wheel.FrozenDeps(
                deps=[],
                deps_select={
                    "osx_aarch64": ["m1_dep", "mac_dep"],
                    "@platforms//os:osx": ["mac_dep"],
                },
            ),
            got,
        )

    def test_deps_from_more_specialized_platforms_are_propagated(self):
        platforms = {
            "osx_x86_64",
            "osx_aarch64",
        }
        got = wheel.Deps(
            "foo",
            requires_dist=[
                "a_mac_dep; sys_platform=='darwin'",
                "m1_dep; sys_platform=='darwin' and platform_machine=='arm64'",
            ],
            platforms=set(wheel.Platform.from_string(platforms)),
        ).build()

        self.assertEqual([], got.deps)
        self.assertEqual(
            {
                "osx_aarch64": ["a_mac_dep", "m1_dep"],
                "@platforms//os:osx": ["a_mac_dep"],
            },
            got.deps_select,
        )

    def test_non_platform_markers_are_added_to_common_deps(self):
        platforms = {
            "linux_x86_64",
            "osx_x86_64",
            "osx_aarch64",
            "windows_x86_64",
        }
        got = wheel.Deps(
            "foo",
            requires_dist=[
                "bar",
                "baz; implementation_name=='cpython'",
                "m1_dep; sys_platform=='darwin' and platform_machine=='arm64'",
            ],
            platforms=set(wheel.Platform.from_string(platforms)),
        ).build()

        self.assertEqual(["bar", "baz"], got.deps)
        self.assertEqual(
            {
                "osx_aarch64": ["m1_dep"],
            },
            got.deps_select,
        )

    def test_self_is_ignored(self):
        deps = wheel.Deps(
            "foo",
            requires_dist=[
                "bar",
                "req_dep; extra == 'requests'",
                "foo[requests]; extra == 'ssl'",
                "ssl_lib; extra == 'ssl'",
            ],
            extras={"ssl"},
        )

        got = deps.build()

        self.assertEqual(["bar", "req_dep", "ssl_lib"], got.deps)
        self.assertEqual({}, got.deps_select)

    def test_self_dependencies_can_come_in_any_order(self):
        deps = wheel.Deps(
            "foo",
            requires_dist=[
                "bar",
                "baz; extra == 'feat'",
                "foo[feat2]; extra == 'all'",
                "foo[feat]; extra == 'feat2'",
                "zdep; extra == 'all'",
            ],
            extras={"all"},
        )

        got = deps.build()

        self.assertEqual(["bar", "baz", "zdep"], got.deps)
        self.assertEqual({}, got.deps_select)


class PlatformTest(unittest.TestCase):
    def test_can_get_host(self):
        host = wheel.Platform.host()
        self.assertIsNotNone(host)
        self.assertEqual(1, len(wheel.Platform.from_string("host")))
        self.assertEqual(host, wheel.Platform.from_string("host"))

    def test_can_get_all(self):
        all_platforms = wheel.Platform.all()
        self.assertEqual(15, len(all_platforms))
        self.assertEqual(all_platforms, wheel.Platform.from_string("all"))

    def test_can_get_all_for_os(self):
        linuxes = wheel.Platform.all(wheel.OS.linux)
        self.assertEqual(5, len(linuxes))
        self.assertEqual(linuxes, wheel.Platform.from_string("linux_*"))

    def test_linux_specializations(self):
        any_linux = wheel.Platform(os=wheel.OS.linux)
        all_specializations = list(any_linux.all_specializations())
        want = [
            wheel.Platform(os=wheel.OS.linux, arch=None),
            wheel.Platform(os=wheel.OS.linux, arch=wheel.Arch.x86_64),
            wheel.Platform(os=wheel.OS.linux, arch=wheel.Arch.x86_32),
            wheel.Platform(os=wheel.OS.linux, arch=wheel.Arch.aarch64),
            wheel.Platform(os=wheel.OS.linux, arch=wheel.Arch.ppc),
            wheel.Platform(os=wheel.OS.linux, arch=wheel.Arch.s390x),
        ]
        self.assertEqual(want, all_specializations)

    def test_osx_specializations(self):
        any_osx = wheel.Platform(os=wheel.OS.osx)
        all_specializations = list(any_osx.all_specializations())
        # NOTE @aignas 2024-01-14: even though in practice we would only have
        # Python on osx aarch64 and osx x86_64, we return all arch posibilities
        # to make the code simpler.
        want = [
            wheel.Platform(os=wheel.OS.osx, arch=None),
            wheel.Platform(os=wheel.OS.osx, arch=wheel.Arch.x86_64),
            wheel.Platform(os=wheel.OS.osx, arch=wheel.Arch.x86_32),
            wheel.Platform(os=wheel.OS.osx, arch=wheel.Arch.aarch64),
            wheel.Platform(os=wheel.OS.osx, arch=wheel.Arch.ppc),
            wheel.Platform(os=wheel.OS.osx, arch=wheel.Arch.s390x),
        ]
        self.assertEqual(want, all_specializations)

    def test_platform_sort(self):
        platforms = [
            wheel.Platform(os=wheel.OS.linux, arch=None),
            wheel.Platform(os=wheel.OS.linux, arch=wheel.Arch.x86_64),
            wheel.Platform(os=wheel.OS.osx, arch=None),
            wheel.Platform(os=wheel.OS.osx, arch=wheel.Arch.x86_64),
            wheel.Platform(os=wheel.OS.osx, arch=wheel.Arch.aarch64),
        ]
        shuffle(platforms)
        platforms.sort()
        want = [
            wheel.Platform(os=wheel.OS.linux, arch=None),
            wheel.Platform(os=wheel.OS.linux, arch=wheel.Arch.x86_64),
            wheel.Platform(os=wheel.OS.osx, arch=None),
            wheel.Platform(os=wheel.OS.osx, arch=wheel.Arch.x86_64),
            wheel.Platform(os=wheel.OS.osx, arch=wheel.Arch.aarch64),
        ]

        self.assertEqual(want, platforms)

    def test_wheel_os_alias(self):
        self.assertEqual("osx", str(wheel.OS.osx))
        self.assertEqual(str(wheel.OS.darwin), str(wheel.OS.osx))

    def test_wheel_arch_alias(self):
        self.assertEqual("x86_64", str(wheel.Arch.x86_64))
        self.assertEqual(str(wheel.Arch.amd64), str(wheel.Arch.x86_64))

    def test_wheel_platform_alias(self):
        give = wheel.Platform(
            os=wheel.OS.darwin,
            arch=wheel.Arch.amd64,
        )
        alias = wheel.Platform(
            os=wheel.OS.osx,
            arch=wheel.Arch.x86_64,
        )

        self.assertEqual("osx_x86_64", str(give))
        self.assertEqual(str(alias), str(give))


if __name__ == "__main__":
    unittest.main()

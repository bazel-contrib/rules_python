(pypi) The default {obj}`pip.default` platforms now cover all of the platforms
of the hermetic Python toolchains: `linux_armv7`, `linux_i386`, `linux_ppc`,
`linux_riscv64`, `linux_s390x`, `linux_x86_64_musl`, `osx_arm64e` and
`windows_x86_32`, together with their `_freethreaded` variants. The glibc Linux
platforms now also match on the {flag}`--py_linux_libc` flag.

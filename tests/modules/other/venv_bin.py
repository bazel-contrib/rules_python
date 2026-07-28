import nspkg

print(nspkg)

import nspkg.subnspkg  # noqa: E402

print(nspkg.subnspkg)

import nspkg.subnspkg.delta  # noqa: E402

print(nspkg.subnspkg.delta)

import nspkg.subnspkg.gamma  # noqa: E402

print(nspkg.subnspkg.gamma)

print("@other//:venv_bin ran successfully.")

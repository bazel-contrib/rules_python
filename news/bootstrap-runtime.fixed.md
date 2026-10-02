(bootstrap) Fixed cancellation and temporary-runtime cleanup across ordinary
binaries, legacy ZIPs, and both entry points of `py_zipapp_binary` and
`py_zipapp_test`. POSIX launchers preserve the application's PID, signal delivery,
and terminal job; cleanup follows interpreter exit. Ordinary runtime-created
virtual environments now prepare in Python. ZIP caches publish only completed
trees, and Python ZIP entry points honor target and additional interpreter
arguments. Paths containing spaces, partial extraction, concurrent startup, and
custom startup templates retain their intended behavior.

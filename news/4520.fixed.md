(zipapp) Zip launchers using the shell bootstrap (`py_zipapp_binary` and
`--build_python_zip` with `bootstrap_impl=script`) now remove their temporary
extraction directory even when they're killed while still unzipping, including
by `SIGHUP`, `SIGTERM` or `SIGKILL`. Previously a partly extracted directory
was left behind in the temporary directory.

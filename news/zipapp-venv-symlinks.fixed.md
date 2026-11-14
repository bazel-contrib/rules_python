(zipapp) {obj}`py_zipapp_binary` stores runfiles symlinks whose target is also
packed in the zipapp, such as the venv `site-packages` entries that point into
pip repositories, as relative symlinks instead of a second copy of the file.

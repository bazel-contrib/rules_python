(zipapp) {obj}`py_zipapp_binary` stores a runfiles symlink whose target file is
also packed in the zipapp, such as a venv `site-packages` shared library that
points into a pip repository, as a relative symlink to the packed file instead
of a second copy, except for Windows targets. Tools that unpack the archive
without symlink support, such as `zipfile.ZipFile.extractall`, now get a small
file holding the link target in its place, as they already did for the venv's
other symlinks.

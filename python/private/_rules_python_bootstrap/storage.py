"""Owned preparation workspaces and complete immutable application images."""

import errno
import os
import shutil
import stat
import tempfile
import zipfile

from .diagnostics import verbose

COMPLETION_FILE = ".rules_python_complete"


class Workspace:
    """Own at most one temporary root; borrowed and published images are separate."""

    def __init__(self, *, directory=None, retain=False):
        self.directory = directory
        self.retain = retain
        self.path = None

    def __enter__(self):
        return self

    def allocate(self):
        if self.path is None:
            self.path = os.path.abspath(
                tempfile.mkdtemp(prefix="rules_python.", dir=self.directory)
            )
            verbose("workspace", self.path)
            if self.retain:
                verbose("retaining workspace", self.path)
        return self.path

    def remove(self):
        if self.path is not None:
            if not self.retain:
                remove_tree(self.path)
            self.path = None

    def __exit__(self, *_error):
        self.remove()


def remove_tree(path):
    """Remove an owned tree, including read-only archive inputs on Windows."""

    def retry_readonly(function, failed_path, error):
        if isinstance(error[1], FileNotFoundError):
            return
        if (
            os.name == "nt"
            and isinstance(error[1], PermissionError)
            and not os.path.islink(failed_path)
        ):
            os.chmod(failed_path, os.stat(failed_path).st_mode | stat.S_IWRITE)
            function(failed_path)
            return
        raise error[1]

    shutil.rmtree(path, onerror=retry_readonly)


def complete_image(path):
    if not os.path.lexists(path):
        return False
    if not os.path.isfile(os.path.join(path, COMPLETION_FILE)):
        raise RuntimeError(
            "Incomplete Python runtime at "
            + os.fspath(path)
            + "; use a clean extract root"
        )
    verbose("using prepared image", path)
    return True


def publish_image(staging, destination):
    """Publish a prepared image, or discard staging in favor of a complete winner."""
    # Restore the normal directory permissions without changing process-wide umask.
    permissions = os.path.join(staging, ".permissions")
    os.mkdir(permissions, 0o777)
    mode = stat.S_IMODE(os.stat(permissions).st_mode)
    os.rmdir(permissions)
    os.chmod(staging, mode)
    with open(os.path.join(staging, COMPLETION_FILE), "w") as stream:
        stream.write("rules_python application 1\n")
    if complete_image(destination):
        remove_tree(staging)
        return

    # POSIX rename can overwrite an empty directory created after an existence
    # check. Keep the completed image separately and publish an exclusive link.
    # This also works on older libc versions without an exclusive rename API.
    parent = os.path.dirname(destination)
    backing = tempfile.mkdtemp(prefix=".rules_python_image.", dir=parent)
    retain_backing = False
    try:
        os.chmod(backing, mode)
        image = os.path.join(backing, "image")
        os.rename(staging, image)
        target = os.path.relpath(image, parent)
        try:
            os.symlink(target, destination, target_is_directory=True)
        except OSError as error:
            # A network filesystem may report failure after creating the link.
            # Never delete an image that may already be visible to readers.
            try:
                retain_backing = os.readlink(destination) == target
            except OSError as inspection:
                if inspection.errno not in (errno.ENOENT, errno.EINVAL):
                    retain_backing = True
                    raise error
            if not retain_backing and (
                error.errno != errno.EEXIST or not complete_image(destination)
            ):
                raise
        else:
            retain_backing = True
        if retain_backing:
            verbose("published image", destination)
    finally:
        if not retain_backing:
            remove_tree(backing)


def extract_archive(archive, destination, cancellation):
    """Materialize a build-produced image, including executable modes and links."""
    verbose("extracting archive", archive, "into", destination)
    os.makedirs(destination)
    links = []
    with zipfile.ZipFile(archive) as source:
        for info in source.infolist():
            cancellation.check()
            path = os.path.abspath(os.path.join(destination, info.filename))
            if os.path.commonpath([destination, path]) != destination:
                raise ValueError(
                    "Archive member escapes application image: " + info.filename
                )
            mode = info.external_attr >> 16
            if stat.S_ISLNK(mode):
                links.append((info.filename, path, source.read(info).decode("utf-8")))
                continue
            source.extract(info, destination)
            if mode:
                os.chmod(path, stat.S_IMODE(mode))
        for name, path, target in links:
            cancellation.check()
            os.makedirs(os.path.dirname(path), exist_ok=True)
            if os.name == "nt":
                target_name = os.path.normpath(
                    os.path.join(os.path.dirname(name), target)
                )
                try:
                    directory = source.getinfo(target_name.replace("\\", "/")).is_dir()
                except KeyError:
                    directory = True
            else:
                directory = False
            os.symlink(target, path, target_is_directory=directory)


def write_atomic(path, contents):
    fd, temporary = tempfile.mkstemp(prefix=".config.", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(contents)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)

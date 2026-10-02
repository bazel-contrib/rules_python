"""Resolve runtime facts and prepare the image's declared Python environment."""

import hashlib
import json
import os
import site
import sys
from dataclasses import dataclass

from .diagnostics import verbose
from .process import run_child
from .storage import write_atomic


@dataclass(frozen=True)
class Runtime:
    executable: str
    prefix: str
    site_packages: str
    version: tuple
    abi: str

    def identity(self, runfiles=None):
        def normalize(path):
            if runfiles and _inside(path, runfiles):
                return "<image>/" + os.path.relpath(path, runfiles)
            return path

        value = [
            normalize(self.executable),
            normalize(self.prefix),
            self.site_packages,
            self.version,
            self.abi,
        ]
        return hashlib.sha256(json.dumps(value).encode("utf-8")).hexdigest()


def current_runtime():
    return Runtime(
        sys.executable,
        sys.base_prefix,
        os.path.normpath(site.getsitepackages(["."])[-1]),
        tuple(sys.version_info[:3]),
        getattr(sys, "abiflags", ""),
    )


def resolve_runtime(interpreter, runfiles, cancellation, *, selected=False):
    executable = interpreter.locate(runfiles)
    verbose("selected interpreter", executable)
    if selected:
        return current_runtime()
    source = (
        "import json,os,site,sys; "
        "print(json.dumps([sys.executable,sys.base_prefix,"
        "os.path.normpath(site.getsitepackages(['.'])[-1]),"
        "list(sys.version_info[:3]),getattr(sys,'abiflags','')]))"
    )
    environment = dict(os.environ)
    if runfiles:
        environment["RUNFILES_DIR"] = runfiles
        environment.pop("RUNFILES_MANIFEST_FILE", None)
    environment.pop("__PYVENV_LAUNCHER__", None)
    values = json.loads(
        run_child(
            [executable, "-I", "-S", "-c", source],
            cancellation,
            capture=True,
            env=environment,
        )
    )
    return Runtime(values[0], values[1], values[2], tuple(values[3]), values[4])


def venv_layout_identity(application, runfiles):
    """Hash preparation inputs without traversing linked dependency trees."""
    venv = application.venv
    digest = hashlib.sha256()
    with open(os.path.join(runfiles, venv.links), "rb") as source:
        links = source.read()
    digest.update(links)
    directories = {"", os.path.dirname(os.path.relpath(venv.executable, venv.root))}
    for line in links.splitlines():
        path, _target = json.loads(line)
        directory = os.path.dirname(os.path.normpath(path))
        while directory:
            directories.add(directory)
            directory = os.path.dirname(directory)
    for directory in sorted(directories):
        path = os.path.join(runfiles, venv.root, directory)
        names = sorted(os.listdir(path)) if os.path.isdir(path) else []
        digest.update(json.dumps([directory, names]).encode("utf-8"))
    # Changing preparation code must invalidate old materializations too.
    for name in (
        "diagnostics.py",
        "environment.py",
        "entry.py",
        "model.py",
        "process.py",
        "storage.py",
    ):
        with open(os.path.join(os.path.dirname(__file__), name), "rb") as source:
            digest.update(source.read())
    return digest.digest()


def _link(path, target, *, replace=False, relative=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    directory = os.path.isdir(target)
    if relative:
        target = os.path.relpath(target, os.path.dirname(path))
    if os.path.lexists(path):
        if not replace:
            return
        if os.path.isdir(path) and not os.path.islink(path):
            raise RuntimeError("Cannot replace directory with runtime link: " + path)
        os.unlink(path)
    os.symlink(target, path, target_is_directory=directory)


def _inside(path, root):
    try:
        return os.path.commonpath(
            [os.path.abspath(path), os.path.abspath(root)]
        ) == os.path.abspath(root)
    except ValueError:
        return False


def _overlay(source, destination, overrides, cancellation):
    """Link whole directories, descending only where explicit links require it."""
    pending = [(source, destination, overrides)]
    while pending:
        src, dst, links = pending.pop()
        cancellation.check()
        if not links:
            if os.path.exists(src):
                _link(dst, src)
            continue
        os.makedirs(dst, exist_ok=True)
        names = set(os.listdir(src)) if os.path.isdir(src) else set()
        branches = {}
        for path, target in links.items():
            first, separator, rest = path.partition(os.sep)
            names.add(first)
            if separator:
                branches.setdefault(first, {})[rest] = target
        for name in names:
            path = os.path.join(dst, name)
            if name in links:
                _link(path, links[name])
            else:
                pending.append((os.path.join(src, name), path, branches.get(name, {})))


def prepare_venv(
    application,
    runfiles,
    destination,
    cancellation,
    *,
    runtime=None,
    image_owned=False,
    final_runfiles=None,
):
    """Prepare only declared runtime-dependent files, preserving the image layout."""
    verbose("preparing environment", destination)
    venv = application.venv
    if venv is None:
        return application.interpreter.locate(runfiles)
    source = os.path.join(runfiles, venv.root)
    actual = (
        runtime.executable
        if runtime is not None
        else application.interpreter.locate(runfiles)
    )
    actual = os.path.abspath(actual)
    relative_executable = os.path.relpath(venv.executable, venv.root)
    executable = os.path.join(destination, relative_executable)
    os.makedirs(destination, exist_ok=True)
    site_packages = runtime.site_packages if runtime is not None else venv.site_packages

    if os.path.abspath(source) != os.path.abspath(destination):
        overrides = {}
        with open(os.path.join(runfiles, venv.links)) as stream:
            for line in stream:
                path, target = json.loads(line)
                overrides[os.path.normpath(path)] = os.path.normpath(
                    os.path.join(runfiles, target)
                )
        # The interpreter is recreated below, never copied as a build-time marker.
        overrides.pop(os.path.normpath(relative_executable), None)
        overrides.pop("pyvenv.cfg", None)
        names = set(os.listdir(source))
        names.update(path.split(os.sep, 1)[0] for path in overrides)
        for name in names:
            cancellation.check()
            if name in (
                "pyvenv.cfg",
                os.path.dirname(relative_executable),
                "lib",
                "Lib",
            ):
                continue
            prefix = name + os.sep
            branch = {
                key[len(prefix) :]: val
                for key, val in overrides.items()
                if key.startswith(prefix)
            }
            if name in overrides:
                _link(os.path.join(destination, name), overrides[name])
            else:
                _overlay(
                    os.path.join(source, name),
                    os.path.join(destination, name),
                    branch,
                    cancellation,
                )
        # Link the site's highest common directory when no overlay is necessary.
        prefix = os.path.normpath(venv.site_packages) + os.sep
        site_links = {
            key[len(prefix) :]: val
            for key, val in overrides.items()
            if key.startswith(prefix)
        }
        _overlay(
            os.path.join(source, venv.site_packages),
            os.path.join(destination, site_packages),
            site_links,
            cancellation,
        )
        bin_name = os.path.dirname(relative_executable)
        bin_source = os.path.join(source, bin_name)
        os.makedirs(os.path.join(destination, bin_name), exist_ok=True)
        if os.path.isdir(bin_source):
            for name in os.listdir(bin_source):
                if name != os.path.basename(executable):
                    _link(
                        os.path.join(destination, bin_name, name),
                        os.path.join(bin_source, name),
                    )
        for path, target in overrides.items():
            if path.startswith(bin_name + os.sep):
                _link(os.path.join(destination, path), target, replace=True)
    elif os.path.normpath(site_packages) != os.path.normpath(venv.site_packages):
        _link(
            os.path.join(destination, site_packages),
            os.path.join(destination, venv.site_packages),
            relative=True,
        )

    cancellation.check()
    relative = image_owned and _inside(actual, runfiles)
    _link(executable, actual, replace=True, relative=relative)
    if os.name == "nt":
        home = runtime.prefix if runtime is not None else os.path.dirname(actual)
        for name in os.listdir(home):
            if name.endswith((".dll", ".pdb")):
                _link(
                    os.path.join(os.path.dirname(executable), name),
                    os.path.join(home, name),
                    replace=True,
                    relative=relative,
                )
        if final_runfiles and relative:
            home = os.path.join(final_runfiles, os.path.relpath(home, runfiles))
        write_atomic(
            os.path.join(destination, "pyvenv.cfg"), "home = {}\n".format(home)
        )
    elif not os.path.lexists(os.path.join(destination, "pyvenv.cfg")):
        if image_owned:
            write_atomic(os.path.join(destination, "pyvenv.cfg"), "")
        else:
            _link(
                os.path.join(destination, "pyvenv.cfg"),
                os.path.join(source, "pyvenv.cfg"),
            )
    cancellation.check()
    return executable

"""The build-produced application contract and resolved launch values."""

import json
import os
import shutil
from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class Interpreter:
    kind: str
    path: str
    resolve: bool

    def locate(self, runfiles):
        if self.kind == "runfiles":
            result = os.path.join(runfiles, self.path)
        elif self.kind == "absolute":
            result = self.path
        elif self.kind == "path":
            result = shutil.which(self.path)
        else:
            raise ValueError("Unknown interpreter kind: " + self.kind)
        if not result or not os.path.isfile(result) or not os.access(result, os.X_OK):
            raise RuntimeError("Python interpreter not executable: " + self.path)
        return os.path.abspath(result)


@dataclass(frozen=True)
class Venv:
    root: str
    executable: str
    site_packages: str
    recreate: bool
    links: str


@dataclass(frozen=True)
class Application:
    entry: str
    workspace: str
    interpreter: Interpreter
    interpreter_args: tuple
    venv: Optional[Venv]
    cleanup: str

    @classmethod
    def read(cls, contents):
        value = json.loads(contents)
        if value.pop("version") != 1:
            raise ValueError("Unsupported rules_python application version")
        value["interpreter"] = Interpreter(**value["interpreter"])
        if value["venv"] is not None:
            value["venv"] = Venv(**value["venv"])
        value["interpreter_args"] = tuple(value["interpreter_args"])
        return cls(**value)


@dataclass(frozen=True)
class PreparedApplication:
    runfiles: str
    executable: str


@dataclass(frozen=True)
class Invocation:
    executable: str
    argv: tuple
    environment: dict
    cwd: Optional[str]


def invocation(
    application, prepared, interpreter_args, arguments, environment, temporary_zip=""
):
    """Construct the final invocation without modifying process state."""
    env = dict(environment)
    env.pop("RULES_PYTHON_ADDITIONAL_INTERPRETER_ARGS", None)
    env.pop("__PYVENV_LAUNCHER__", None)
    env["RUNFILES_DIR"] = prepared.runfiles
    env.setdefault("PYTHONSAFEPATH", "1")
    if temporary_zip:
        env.pop("RUNFILES_MANIFEST_FILE", None)
    if env.get("RULES_PYTHON_TESTING_TELL_RUNFILES_ROOT"):
        env["RULES_PYTHON_TESTING_RUNFILES_ROOT"] = prepared.runfiles
    cwd = None
    if env.get("RUN_UNDER_RUNFILES") == "1":
        cwd = os.path.join(prepared.runfiles, application.workspace)
    options = list(interpreter_args)
    if temporary_zip:
        options.insert(0, "-XRULES_PYTHON_ZIP_DIR=" + temporary_zip)
    entry = os.path.join(prepared.runfiles, application.entry)
    if not os.path.isfile(entry):
        raise RuntimeError("Application entry point not found: " + entry)
    return Invocation(
        prepared.executable,
        tuple([prepared.executable] + options + [entry] + list(arguments)),
        env,
        cwd,
    )

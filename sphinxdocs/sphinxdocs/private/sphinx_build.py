from __future__ import annotations

import concurrent.futures
import contextlib
import io
import json
import logging
import os
import pathlib
import shutil
import stat
import sys
import threading
import traceback
import types
from typing import TextIO, TypedDict

import sphinx.application  # pyrefly: ignore[missing-import]
from sphinx.cmd.build import main  # pyrefly: ignore[missing-import]


class WorkRequestInput(TypedDict, total=False):
    """Input file with digest for a Bazel persistent worker WorkRequest.

    See https://github.com/bazelbuild/bazel/blob/master/src/main/protobuf/worker_protocol.proto (Input message).
    """

    path: str
    digest: str


class WorkRequest(TypedDict, total=False):
    """Bazel persistent worker WorkRequest protocol structure.

    See https://github.com/bazelbuild/bazel/blob/master/src/main/protobuf/worker_protocol.proto (WorkRequest message).
    """

    id: int
    requestId: int
    arguments: list[str]
    inputs: list[WorkRequestInput]
    cancel: bool


class WorkResponse(TypedDict, total=False):
    """Bazel persistent worker WorkResponse protocol structure.

    See https://github.com/bazelbuild/bazel/blob/master/src/main/protobuf/worker_protocol.proto (WorkResponse message).
    """

    id: int
    requestId: int
    exitCode: int
    output: str
    wasCancelled: bool


class RequestInfo(TypedDict, total=False):
    """JSON structure written for the Sphinx extension with worker request metadata."""

    exec_root: str
    inputs: list[WorkRequestInput]
    changed_sources: list[str]


class SphinxMainError(Exception):
    def __init__(self, message, exit_code):
        super().__init__(message)
        self.exit_code = exit_code


logger = logging.getLogger("sphinxdocs_build")

_WORKER_SPHINX_EXT_MODULE_NAME = "bazel_worker_sphinx_ext"

# Config value name for getting the path to the request info file
_REQUEST_INFO_CONFIG_NAME = "bazel_worker_request_info_path"


class DirectorySyncerError(Exception):
    """Raised when one or more errors occur during directory synchronization."""

    def __init__(self, errors: list[BaseException]):
        self.errors = errors
        message = f"Encountered {len(errors)} error(s) during sync:\n" + "\n".join(
            f"  - {e}" for e in errors
        )
        super().__init__(message)


class DirectorySyncer:
    """Synchronizes a working destination directory from a source directory.

    Supports concurrent SHA-aware incremental updates (via sync()) for worker
    mode and concurrent full directory copying (via copytree()) for non-worker
    mode, ensuring physical file materialization to prevent relative
    cross-reference resolution failures.
    """

    def __init__(
        self,
        srcdir: pathlib.Path,
        destdir: pathlib.Path,
        max_workers: int | None = None,
    ):
        self._srcdir = srcdir
        self._destdir = destdir
        self._max_workers = max_workers or min(32, (os.cpu_count() or 4) + 4)
        self._current_shas: dict[str, str] = {}
        self._lock = threading.Lock()
        self._finished_cond = threading.Condition(self._lock)
        self._remaining = 0
        self._errors: list[BaseException] = []
        self._executor: concurrent.futures.ThreadPoolExecutor | None = None

    def _reset_state(self) -> None:
        with self._lock:
            self._errors.clear()
            self._remaining = 0

    def _wait_for_completion(self) -> None:
        with self._lock:
            while self._remaining > 0:
                self._finished_cond.wait()
        if self._errors:
            raise DirectorySyncerError(list(self._errors))

    def _submit_task(self, fn, *args) -> None:
        with self._lock:
            self._remaining += 1
        assert self._executor is not None
        future = self._executor.submit(fn, *args)
        future.add_done_callback(self._handle_task_done)

    def _handle_task_done(self, future: concurrent.futures.Future) -> None:
        exc = future.exception()
        if exc:
            with self._lock:
                self._errors.append(exc)

    def _task_finished(self) -> None:
        with self._lock:
            self._remaining -= 1
            if self._remaining == 0:
                self._finished_cond.notify_all()

    @contextlib.contextmanager
    def _create_executor(self):
        with concurrent.futures.ThreadPoolExecutor(
            max_workers=self._max_workers
        ) as executor:
            self._executor = executor
            try:
                yield
            finally:
                self._executor = None

    def copytree(self) -> None:
        """Concurrently copies srcdir to destdir without SHA tracking."""
        self._reset_state()
        shutil.rmtree(self._destdir, ignore_errors=True)
        with self._create_executor():
            self._submit_task(self._copy_dir, self._srcdir, self._destdir)
            self._wait_for_completion()

    def sync(self, entries: dict[str, str]) -> None:
        """Synchronizes destdir to match entries {relative_path: sha} concurrently."""
        self._reset_state()

        to_remove = set(self._current_shas.keys()) - set(entries.keys())
        to_copy = {
            path: sha
            for path, sha in entries.items()
            if self._current_shas.get(path) != sha
        }

        if not to_remove and not to_copy:
            self._current_shas = dict(entries)
            return

        with self._create_executor():
            # 1. Submit stale path removals concurrently ASAP
            for rel_path in to_remove:
                dest_path = self._destdir / rel_path
                self._submit_task(self._remove_path, dest_path)

            # 2. Submit created/updated item copies concurrently ASAP
            for rel_path in to_copy:
                src_path = self._srcdir / rel_path
                dest_path = self._destdir / rel_path
                if src_path.is_dir():
                    self._submit_task(self._copy_dir, src_path, dest_path)
                else:
                    self._submit_task(self._copy_file, src_path, dest_path)

            self._wait_for_completion()

        self._current_shas = dict(entries)

    def _remove_path(self, dest_path: pathlib.Path) -> None:
        try:
            if dest_path.is_dir() and not dest_path.is_symlink():
                shutil.rmtree(dest_path)
            else:
                dest_path.unlink(missing_ok=True)
        except BaseException as e:
            e.add_note(f"Failed removing path: dest_path={dest_path}")
            raise
        finally:
            self._task_finished()

    def _copy_file(self, src: pathlib.Path, dest: pathlib.Path) -> None:
        try:
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dest)
            mode = dest.stat().st_mode
            dest.chmod(mode | stat.S_IWUSR)
        except BaseException as e:
            e.add_note(f"Failed copying file: src={src}, dest={dest}")
            raise
        finally:
            self._task_finished()

    def _copy_dir(self, src: pathlib.Path, dest: pathlib.Path) -> None:
        """Recursively creates destination directory and submits tasks for its entries."""
        try:
            dest.mkdir(parents=True, exist_ok=True)
            with os.scandir(src) as scanner:
                for entry in scanner:
                    c_dest = dest / entry.name
                    c_src = pathlib.Path(entry.path)
                    if entry.is_dir():
                        self._submit_task(self._copy_dir, c_src, c_dest)
                    else:
                        self._submit_task(self._copy_file, c_src, c_dest)
        except BaseException as e:
            e.add_note(f"Failed copying directory: src={src}, dest={dest}")
            raise
        finally:
            self._task_finished()


class Worker:
    """A Bazel persistent worker for Sphinx builds."""

    def __init__(self, instream: TextIO, outstream: TextIO, exec_root: str):
        # NOTE: Sphinx performs its own logging re-configuration, so any
        # logging config we do isn't respected by Sphinx. Controlling where
        # stdout and stderr goes are the main mechanisms. Recall that
        # Bazel send worker stderr to the worker log file.
        # outputBase=$(bazel info output_base)
        # find $outputBase/bazel-workers/ -type f -printf '%T@ %p\n' | sort -n | tail -1 | awk '{print $2}'
        logging.basicConfig(level=logging.WARN)
        logger.info("Initializing worker")

        # The directory that paths are relative to.
        self._exec_root = exec_root
        # Where requests are read from.
        self._instream = instream
        # Where responses are written to.
        self._outstream = outstream

        # dict[str srcdir, dict[str path, str digest]]
        self._digests = {}
        self._syncers: dict[pathlib.Path, DirectorySyncer] = {}

        # Internal output directories the worker gives to Sphinx that need
        # to be cleaned up upon exit.
        # set[str path]
        self._worker_outdirs = set()
        self._extension = BazelWorkerExtension()

        sys.modules[_WORKER_SPHINX_EXT_MODULE_NAME] = self._extension
        sphinx.application.builtin_extensions += (_WORKER_SPHINX_EXT_MODULE_NAME,)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        for worker_outdir in self._worker_outdirs:
            shutil.rmtree(worker_outdir, ignore_errors=True)

    def run(self) -> None:
        logger.info("Worker started")
        try:
            while True:
                request = None
                try:
                    request = self._get_next_request()
                    if request is None:
                        logger.info("Empty request: exiting")
                        break
                    response = self._process_request(request)
                    if response:
                        self._send_response(response)
                except SphinxMainError as e:
                    logger.error(
                        "Sphinx main returned failure: exit_code=%s request=%s",
                        request,
                        e.exit_code,
                    )
                    request_id = 0 if not request else request.get("requestId", 0)
                    self._send_response(
                        {
                            "exitCode": e.exit_code,
                            "output": str(e),
                            "requestId": request_id,
                        }
                    )
                except Exception:
                    logger.exception("Unhandled error: request=%s", request)
                    request_id = request.get("requestId", 0) if request else 0
                    req_id_str = request.get("id") if request else "unknown"
                    output = (
                        f"Unhandled error:\nRequest id: {req_id_str}\n"
                        + traceback.format_exc()
                    )
                    self._send_response(
                        {
                            "exitCode": 3,
                            "output": output,
                            "requestId": request_id,
                        }
                    )
        finally:
            logger.info("Worker shutting down")

    def _get_next_request(self) -> WorkRequest | None:
        line = self._instream.readline()
        if not line:
            return None
        return json.loads(line)

    def _send_response(self, response: WorkResponse) -> None:
        self._outstream.write(json.dumps(response) + "\n")
        self._outstream.flush()

    def _prepare_sphinx(self, request: WorkRequest):
        sphinx_args = request.get("arguments", [])
        srcdir = pathlib.Path(sphinx_args[0])
        destdir = pathlib.Path(f"{srcdir}.worker-in.d")

        incoming_digests = {}
        current_digests = self._digests.setdefault(str(srcdir), {})
        is_first_request = not current_digests
        changed_paths = []
        request_info: RequestInfo = {
            "exec_root": self._exec_root,
            "inputs": request.get("inputs", []),
        }
        srcdir_prefix = str(srcdir) + "/"
        for entry in request.get("inputs", []):
            path = entry["path"]
            # In persistent worker mode, request["inputs"] includes action-level
            # tools (e.g. sphinx-build, sphinx_build.py) and params files that
            # live outside srcdir. Only synchronize documentation sources inside srcdir.
            if not path.startswith(srcdir_prefix):
                continue
            digest = entry["digest"]
            # Make the path srcdir-relative so Sphinx understands it.
            path = path.removeprefix(srcdir_prefix)
            incoming_digests[path] = digest

            if path not in current_digests:
                logger.info("path %s new", path)
                changed_paths.append(path)
            elif current_digests[path] != digest:
                logger.info("path %s changed", path)
                changed_paths.append(path)

        self._digests[str(srcdir)] = incoming_digests
        self._extension.changed_paths = set(changed_paths)
        request_info["changed_sources"] = changed_paths

        bazel_outdir = sphinx_args[1]
        worker_outdir = bazel_outdir + ".worker-out.d"
        # The doctree dir deliberately lives outside the declared outputs so
        # it survives between invocations (that is what makes worker builds
        # incremental). A new worker has no digest history: it reports every
        # file as changed and re-reads all docs. Doing that against the stale
        # Sphinx environment of a previous worker produces spurious warnings
        # (e.g. duplicate labels), which --fail-on-warning turns into build
        # failures. So on the first request start from a clean slate.
        if is_first_request:
            shutil.rmtree(worker_outdir, ignore_errors=True)
            shutil.rmtree(destdir, ignore_errors=True)
            for arg in sphinx_args:
                if arg.startswith("--doctree-dir="):
                    shutil.rmtree(arg.partition("=")[2], ignore_errors=True)
        self._worker_outdirs.add(worker_outdir)
        sphinx_args[1] = worker_outdir

        if srcdir not in self._syncers:
            self._syncers[srcdir] = DirectorySyncer(srcdir, destdir)
        syncer = self._syncers[srcdir]
        syncer.sync(incoming_digests)

        sphinx_args[0] = str(destdir)
        request_info_path = os.path.join(
            sphinx_args[0], "_bazel_worker_request_info.json"
        )
        with open(request_info_path, "w") as fp:
            json.dump(request_info, fp)
        sphinx_args.append(f"--define={_REQUEST_INFO_CONFIG_NAME}={request_info_path}")

        return worker_outdir, bazel_outdir, sphinx_args

    @contextlib.contextmanager
    def _redirect_streams(self):
        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            yield stdout, stderr

    def _process_request(self, request: WorkRequest) -> WorkResponse | None:
        logger.info("Request: %s", json.dumps(request, sort_keys=True, indent=2))
        if request.get("cancel"):
            return None

        worker_outdir, bazel_outdir, sphinx_args = self._prepare_sphinx(request)

        # Prevent anything from going to stdout because it breaks the worker
        # protocol. We have limited control over where Sphinx sends output.
        with self._redirect_streams() as (stdout, stderr):
            logger.info("main args: %s", sphinx_args)
            exit_code = main(sphinx_args)
            # Running Sphinx multiple times in a process can give spurious
            # errors. An invocation after an error seems to work, though.
            if exit_code == 2:
                logger.warning("Sphinx main() returned exit_code=2, retrying...")
                # Reset streams to capture output of the retry cleanly
                stdout.seek(0)
                stdout.truncate(0)
                stderr.seek(0)
                stderr.truncate(0)
                # If Sphinx cache (`--doctree-dir`) becomes corrupted across incremental
                # updates or branch checkouts, exit code 2 is returned. Wiping out the cached
                # doctrees before retrying allows Sphinx to recover cleanly from scratch.
                for arg in sphinx_args:
                    if arg.startswith("--doctree-dir="):
                        shutil.rmtree(arg.split("=", 1)[1], ignore_errors=True)
                exit_code = main(sphinx_args)

        if exit_code:
            stdout_output = stdout.getvalue().strip()
            stderr_output = stderr.getvalue().strip()
            if stdout_output:
                stdout_output = (
                    "========== STDOUT START ==========\n"
                    + stdout_output
                    + "\n"
                    + "========== STDOUT END ==========\n"
                )
            else:
                stdout_output = "========== STDOUT EMPTY ==========\n"
            if stderr_output:
                stderr_output = (
                    "========== STDERR START ==========\n"
                    + stderr_output
                    + "\n"
                    + "========== STDERR END ==========\n"
                )
            else:
                stderr_output = "========== STDERR EMPTY ==========\n"

            message = (
                "Sphinx main() returned failure: "
                + f"  exit code: {exit_code}\n"
                + stdout_output
                + stderr_output
            )
            raise SphinxMainError(message, exit_code)

        # Copying is unfortunately necessary because Bazel doesn't know to
        # implicily bring along what the symlinks point to.
        shutil.copytree(worker_outdir, bazel_outdir, dirs_exist_ok=True)

        # Include both stdout and stderr in the response output so that Sphinx
        # warnings or diagnostic messages written to stderr are reported to the
        # Bazel console even when the build succeeds.
        stdout_output = stdout.getvalue()
        stderr_output = stderr.getvalue()
        if stderr_output:
            output = f"--- STDOUT ---\n{stdout_output}\n--- STDERR ---\n{stderr_output}"
        else:
            output = stdout_output

        response = {
            "requestId": request.get("requestId", 0),
            "output": output,
            "exitCode": 0,
        }
        return response


class BazelWorkerExtension(types.ModuleType):
    """A Sphinx extension implemented as a class acting like a module."""

    def __init__(self, name: str = _WORKER_SPHINX_EXT_MODULE_NAME):
        super().__init__(name)
        # set[str] of src-dir relative path names
        self.changed_paths: set[str] = set()

    def setup(self, app):
        app.add_config_value(_REQUEST_INFO_CONFIG_NAME, "", "")
        app.connect("env-get-outdated", self._handle_env_get_outdated)
        return {"parallel_read_safe": True, "parallel_write_safe": True}

    def _handle_env_get_outdated(self, app, env, added, changed, removed):
        changed_docs = set()
        for p in self.changed_paths:
            # Try multiple path resolutions because depending on how Sphinx and Bazel
            # represent inputs (`p`), `env.path2doc` may require relative, srcdir-joined,
            # or absolute paths to successfully resolve the document name.
            doc = (
                env.path2doc(p)
                or env.path2doc(os.path.join(env.srcdir, p))
                or env.path2doc(os.path.abspath(os.path.join(env.srcdir, p)))
            )
            if doc:
                changed_docs.add(doc)

        # When documents are added or removed across incremental builds or branch checkouts,
        # parent documents whose `toctree` includes them (especially via glob patterns or
        # explicit references to removed docs) must be invalidated and re-read. Otherwise,
        # Sphinx retains stale table of contents entries or throws unresolvable reference errors.
        if added or removed:
            glob_toctrees = getattr(env, "glob_toctrees", set())
            for doc, includes in getattr(env, "toctree_includes", {}).items():
                if doc in glob_toctrees or not removed.isdisjoint(includes):
                    changed_docs.add(doc)

        logger.info("changed docs: %s", changed_docs)
        return changed_docs


def _worker_main(stdin, stdout, exec_root):
    with Worker(stdin, stdout, exec_root) as worker:
        return worker.run()


def _non_worker_main():
    args = []
    for arg in sys.argv:
        if arg.startswith("@"):
            with open(arg.removeprefix("@")) as fp:
                lines = [line.strip() for line in fp if line.strip()]
            args.extend(lines)
        else:
            args.append(arg)
    if len(args) > 1:
        srcdir = pathlib.Path(args[1])
        destdir = pathlib.Path(f"{srcdir}.worker-in.d")
        DirectorySyncer(srcdir, destdir).copytree()
        args[1] = str(destdir)
    sys.argv[:] = args
    return main()


if __name__ == "__main__":
    if "--persistent_worker" in sys.argv:
        sys.exit(_worker_main(sys.stdin, sys.stdout, os.getcwd()))
    else:
        sys.exit(_non_worker_main())

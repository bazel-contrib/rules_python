from pathlib import Path

import argparse
import json
import logging
import os
import pathlib
import sys
import time
import traceback
import typing

from sphinx.cmd.build import main


WorkRequest = object
WorkResponse = object


parser = argparse.ArgumentParser(
    fromfile_prefix_chars='@'
)
# parser.add_argument('srcdir')
# parser.add_argument('outdir')
parser.add_argument("--persistent_worker", action="store_true")
parser.add_argument("--doctree-dir")


class Worker:

    def __init__(self, instream: "typing.TextIO", outstream: "typing.TextIO"):
        self._instream = instream
        self._outstream = outstream
        self._logger = logging.getLogger("worker")
        logging.basicConfig(filename='echo.log', encoding='utf-8', level=logging.DEBUG)
        self._logger.info("starting worker")
        self._current = {}
        self._previous = {}
        self._cache = {}

    def run(self) -> None:
        try:
            while True:
                request = None
                try:
                    request = self._get_next_request()
                    if request is None:
                        self._logger.info("Empty request: exiting")
                        break
                    response = self._process_request(request)
                    if response:
                        self._send_response(response)
                except Exception:
                    self._logger.exception("Unhandled error: request=%s", request)
                    output = (
                        f"Unhandled error:\nRequest: {request}\n"
                        + traceback.format_exc()
                    )
                    request_id = 0 if not request else request.get("requestId", 0)
                    self._send_response(
                        {
                            "exitCode": 3,
                            "output": output,
                            "requestId": request_id,
                        }
                    )
        finally:
            self._logger.info("Worker shutting down")

    def _get_next_request(self) -> "object | None":
        line = self._instream.readline()
        if not line:
            return None
        return json.loads(line)

    @property
    def inputs(self):
        self._previous
        self._current
        return self._value

    def _update_digest(self, request):
        args, unknown = parser.parse_known_args(request["arguments"])
        # Make room for the new build's data. 
        self._previous = self._current
        # Rearrange the new data into a dict to make comparisons easier.
        self._current = {}
        for page in request["inputs"]:
            path = page["path"]
            self._current[path] = page["digest"]
        # Compare the content hashes to determine what pages have changed.
        changed_paths = []
        for path in self._current:
            if path not in self._previous:
                changed_paths.append(path)
                continue
            if self._current[path] != self._previous[path]:
                changed_paths.append(path)
                continue
        for path in self._previous:
            if path not in self._current:
                changed_paths.append(path)
                continue
        # Normalize the paths into docnames
        digest = []
        for path in changed_paths:
            if not path.endswith(".rst"):
                continue
            srcdir = self.args[0]
            docname = path.replace(srcdir + "/", "")
            docname = docname.replace(".rst", "")
            digest.append(docname)
        args, unknown = parser.parse_known_args(self.args)
        # Save the digest.
        doctree_dir = Path(args.doctree_dir)
        # On a fresh build, _restore_cache() does nothing, so this dir won't exist yet.
        if not doctree_dir.is_dir():
            doctree_dir.mkdir(parents=True)
        with open(doctree_dir / Path("digest.json"), "w") as f:
            json.dump(digest, f, indent=2)

    def _restore_cache(self):
        for filepath in self._cache:
            data = self._cache[filepath]
            parent = Path(os.path.dirname(filepath))
            if not parent.is_dir():
                parent.mkdir(parents=True)
            with open(filepath, "wb") as f:
                f.write(data)

    def _update_cache(self):
        args, unknown = parser.parse_known_args(self.args)
        self._cache = {}
        for root, _, files in os.walk(args.doctree_dir):
            for filename in files:
                filepath = Path(root) / Path(filename)
                with open(filepath, "rb") as f:
                    self._cache[str(filepath)] = f.read()

    def _process_request(self, request: "WorkRequest") -> "WorkResponse | None":
        if request.get("cancel"):
            return None
        self.args = request["arguments"]
        self._restore_cache()
        self._update_digest(request)
        main(self.args)
        self._update_cache()
        response = {
            "requestId": request.get("requestId", 0),
            "exitCode": 0,
        }
        return response

    def _send_response(self, response: "WorkResponse") -> None:
        self._outstream.write(json.dumps(response) + "\n")
        self._outstream.flush()


if __name__ == "__main__":
    args, unknown = parser.parse_known_args()
    if args.persistent_worker:
        Worker(sys.stdin, sys.stdout).run()
    else:
        sys.exit(main())

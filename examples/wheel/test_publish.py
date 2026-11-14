import os
import socket
import subprocess
import textwrap
import time
import unittest
from contextlib import closing
from pathlib import Path
from urllib.error import URLError
from urllib.request import urlopen

_WHEELMAKER_IMPL = os.environ["WHEELMAKER_IMPL"]
# Rust wheelmaker (flate2) and Python wheelmaker.py (zlib) emit deterministic
# but distinct RFC 1951 DEFLATE streams.
_EXPECTED_WHEEL_SHA256 = {
    # keep-sorted start
    "python": "ef5afd9f6c3ff569ef7e5b2799d3a2ec9675d029414f341e0abd7254d6b9a25d",
    "rust": "abb3ff8d5bb5142cdb476b46e91f586043e10a540170ed66050fbc5c1e19ae32",
    # keep-sorted end
}


def find_free_port():
    with closing(socket.socket(socket.AF_INET, socket.SOCK_STREAM)) as s:
        s.bind(("", 0))
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        return s.getsockname()[1]


class TestTwineUpload(unittest.TestCase):
    def setUp(self):
        self.maxDiff = 1000
        self.port = find_free_port()
        self.url = f"http://localhost:{self.port}"
        self.dir = Path(os.environ["TEST_TMPDIR"])

        self.log_file = self.dir / "pypiserver-log.txt"
        self.log_file.touch()
        _storage_dir = self.dir / "data"
        for d in [_storage_dir]:
            d.mkdir(exist_ok=True)

        print("Starting PyPI server...")
        self._server = subprocess.Popen(
            [
                str(Path(os.environ["SERVER_PATH"])),
                "run",
                "--verbose",
                "--log-file",
                str(self.log_file),
                "--host",
                "localhost",
                "--port",
                str(self.port),
                # Allow unauthenticated access
                "--authenticate",
                ".",
                "--passwords",
                ".",
                str(_storage_dir),
            ],
        )

        interval = 0.1
        wait_seconds = 40
        for _ in range(int(wait_seconds / interval)):  # 40 second timeout
            try:
                with urlopen(self.url, timeout=1) as response:
                    if response.status == 200:
                        break
            except (URLError, OSError):
                pass
            time.sleep(interval)
        else:
            raise RuntimeError(
                f"Could not get the server running fast enough, waited for {wait_seconds}s"
            )

    def tearDown(self):
        self._server.terminate()
        print(f"Stopped PyPI server, all logs:\n{self.log_file.read_text()}")

    def test_upload_and_query_simple_api(self):
        # Given
        script_path = Path(os.environ["PUBLISH_PATH"])
        whl = Path(os.environ["WHEEL_PATH"])

        # When I publish a whl to a package registry
        subprocess.check_output(
            [
                str(script_path),
                "--no-color",
                "upload",
                str(whl),
                "--verbose",
                "--non-interactive",
                "--disable-progress-bar",
            ],
            env={
                "TWINE_REPOSITORY_URL": self.url,
                "TWINE_USERNAME": "dummy",
                "TWINE_PASSWORD": "dummy",
            },
        )

        # Then I should be able to get its contents
        want_sha256 = _EXPECTED_WHEEL_SHA256[_WHEELMAKER_IMPL]
        with urlopen(self.url + "/example-minimal-library/") as response:
            got_content = response.read().decode("utf-8")
            want_content = f"""
<!DOCTYPE html>
<html lang="en">
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Links for example-minimal-library</title>
    </head>
    <body>
        <h1>Links for example-minimal-library</h1>
            <a href="/packages/example_minimal_library-0.0.1-py3-none-any.whl#sha256={want_sha256}">example_minimal_library-0.0.1-py3-none-any.whl</a><br>
    </body>
</html>"""
            self.assertEqual(
                textwrap.dedent(want_content).strip(),
                textwrap.dedent(got_content).strip(),
            )


if __name__ == "__main__":
    unittest.main()

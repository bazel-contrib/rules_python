import base64
import hashlib
import http.server
import io
import os
import socket
import threading
import time
import unittest
import zipfile
from contextlib import closing
from pathlib import Path
from urllib.error import URLError
from urllib.request import Request, urlopen

from tests.integration import runner


def find_free_port():
    with closing(socket.socket(socket.AF_INET, socket.SOCK_STREAM)) as s:
        s.bind(("", 0))
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        return s.getsockname()[1]


def _create_wheel_bytes(name, version):
    """Create a minimal Python wheel in memory.

    Args:
        name: The package name (e.g. "my-local-pkg").
        version: The version string.
    Returns:
        The wheel data as bytes, and the sha256 digest.
    """
    pkg_name_normalized = name.replace("-", "_")
    wheel_name = "{}-{}-py3-none-any.whl".format(pkg_name_normalized, version)
    dist_info = "{}-{}.dist-info".format(pkg_name_normalized, version)

    metadata = (
        "Metadata-Version: 2.1\n"
        "Name: {name}\n"
        "Version: {version}\n"
        "Summary: A test package\n"
    ).format(name=pkg_name_normalized, version=version)

    wheel_file = (
        "Wheel-Version: 1.0\n"
        "Generator: test\n"
        "Root-Is-Purelib: true\n"
        "Tag: py3-none-any\n"
    )

    record_entries = [
        "{}/__init__.py,".format(pkg_name_normalized),
        "{}/METADATA,".format(dist_info),
        "{}/WHEEL,".format(dist_info),
        "{}/RECORD,".format(dist_info),
    ]

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("{}/__init__.py".format(pkg_name_normalized), "# empty\n")
        zf.writestr("{}/METADATA".format(dist_info), metadata)
        zf.writestr("{}/WHEEL".format(dist_info), wheel_file)
        zf.writestr("{}/RECORD".format(dist_info), "\n".join(record_entries))

    wheel_data = buf.getvalue()
    sha256 = hashlib.sha256(wheel_data).hexdigest()
    return wheel_data, sha256, wheel_name


class AuthSimpleAPIHandler(http.server.SimpleHTTPRequestHandler):
    """An HTTP server that serves a PyPI Simple API with Basic auth."""

    def __init__(self, *args, username="", password="", directory="", **kwargs):
        self._username = username
        self._password = password
        super().__init__(*args, directory=directory, **kwargs)

    def _check_auth(self):
        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Basic "):
            return False
        try:
            decoded = base64.b64decode(auth[6:]).decode("utf-8")
            user, _, passwd = decoded.partition(":")
            return user == self._username and passwd == self._password
        except Exception:
            return False

    def do_GET(self):
        if not self._check_auth():
            self.send_response(401)
            self.send_header("WWW-Authenticate", 'Basic realm="PyPI"')
            self.end_headers()
            return
        super().do_GET()


class UvLockIntegrationTest(runner.TestCase):
    def setUp(self):
        super().setUp()

        self.port = find_free_port()
        self.username = "testuser"
        self.password = "secretpass"
        self.server_url = "http://localhost:{port}".format(port=self.port)
        self.index_url = "http://{user}:{passwd}@localhost:{port}".format(
            user=self.username,
            passwd=self.password,
            port=self.port,
        )
        self.auth_url = self.index_url

        self.dir = Path(os.environ["TEST_TMPDIR"])
        self.docroot = self.dir / "simple"
        self.docroot.mkdir(exist_ok=True)

        # Create the test wheel
        self.wheel_data, self.wheel_sha256, wheel_name = _create_wheel_bytes(
            "my-local-pkg",
            "1.0.0",
        )

        # Write the wheel under the docroot
        packages_dir = self.docroot / "packages"
        packages_dir.mkdir(exist_ok=True)
        self.wheel_path = packages_dir / wheel_name
        self.wheel_path.write_bytes(self.wheel_data)

        # Create the package index page for the simple API
        pkg_dir = self.docroot / "my-local-pkg"
        pkg_dir.mkdir(exist_ok=True)
        pkg_index = pkg_dir / "index.html"
        pkg_index.write_text(
            "<html><body>\n"
            '  <a href="../packages/{name}#sha256={sha256}">'
            "{name}</a><br>\n"
            "</body></html>\n".format(name=wheel_name, sha256=self.wheel_sha256)
        )

        # Create the root index page
        root_index = self.docroot / "index.html"
        root_index.write_text(
            "<html><body>\n"
            '  <a href="/my-local-pkg/">my-local-pkg</a><br>\n'
            "</body></html>\n"
        )

        # Start the HTTP server
        self._start_server()

    def _start_server(self):
        server = http.server.HTTPServer(
            ("localhost", self.port),
            lambda *args, **kwargs: AuthSimpleAPIHandler(
                *args,
                username=self.username,
                password=self.password,
                directory=str(self.docroot),
                **kwargs,
            ),
        )
        self._server_thread = threading.Thread(target=server.serve_forever)
        self._server_thread.daemon = True
        self._server_thread.start()

        # Build the auth header for health checks
        auth_header = "Basic " + base64.b64encode(
            "{user}:{passwd}".format(
                user=self.username,
                passwd=self.password,
            ).encode("utf-8")
        ).decode("utf-8")
        interval = 0.1
        wait_seconds = 40
        for _ in range(int(wait_seconds / interval)):
            try:
                req = Request(self.server_url)
                req.add_header("Authorization", auth_header)
                with urlopen(req, timeout=1) as response:
                    if response.status == 200:
                        break
            except (URLError, OSError):
                pass
            time.sleep(interval)
        else:
            raise RuntimeError(
                "Could not start the server, waited for {}s".format(wait_seconds)
            )

    def test_lock_update_with_custom_index(self):
        """Verify that lock.update uses env var from the shell environment."""
        # Verify the server requires auth
        req = Request(self.server_url + "/my-local-pkg/")
        try:
            urlopen(req, timeout=5)
            self.fail("Expected 401 without auth")
        except URLError:
            # Expected - auth required
            pass

        # Verify with auth works
        auth_header = "Basic " + base64.b64encode(
            "{user}:{passwd}".format(
                user=self.username,
                passwd=self.password,
            ).encode("utf-8")
        ).decode("utf-8")
        req = Request(self.server_url + "/my-local-pkg/")
        req.add_header("Authorization", auth_header)
        response = urlopen(req, timeout=5)
        self.assertEqual(response.status, 200)

        # Run the lock.update with UV_EXTRA_INDEX_URL set via --action_env
        result = self.run_bazel(
            "run",
            "--action_env={key}={value}".format(
                key="UV_EXTRA_INDEX_URL",
                value=self.auth_url,
            ),
            "//:requirements.update",
        )
        self.assertEqual(
            result.exit_code,
            0,
            "Lock update failed:\n{}".format(result.describe()),
        )

        # Verify the lock file was created
        lock_file = self.repo_root / "requirements.txt"
        self.assertTrue(lock_file.exists(), "Lock file was not created")
        contents = lock_file.read_text()
        self.assertIn("my-local-pkg", contents)
        self.assertIn(self.wheel_sha256, contents)


if __name__ == "__main__":
    unittest.main()

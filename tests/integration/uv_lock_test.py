import base64
import hashlib
import os
import re
import threading
import time
import unittest
import uuid
from pathlib import Path
from urllib.error import URLError
from urllib.request import Request, urlopen
from wsgiref.simple_server import make_server

from pypiserver import app_from_config, setup_routes_from_config
from pypiserver.config import Config

from tests.integration import runner
from tests.integration.uv_lock_pypi_server import _create_wheel_bytes


def _make_server_on_free_port(app):
    server = make_server("localhost", 0, app)
    port = server.server_address[1]
    return server, port


class UvLockIntegrationTest(runner.TestCase):
    def setUp(self):
        super().setUp()

        self.username = "testuser"
        self.password = uuid.uuid4().hex

        self.dir = Path(os.environ["TEST_TMPDIR"])
        self.docroot = self.dir / "simple"
        self.docroot.mkdir(exist_ok=True)

        self.wheel_data, self.wheel_sha256, wheel_name = _create_wheel_bytes(
            "my-local-pkg",
            "1.0.0",
        )

        packages_dir = self.docroot / "packages"
        packages_dir.mkdir(exist_ok=True)
        self.wheel_path = packages_dir / wheel_name
        self.wheel_path.write_bytes(self.wheel_data)

        config = Config.default_with_overrides(
            roots=[packages_dir],
            port=0,
            host="localhost",
            authenticate=["download", "list", "update"],
            password_file=None,
            auther=lambda u, p: u == self.username and p == self.password,
            disable_fallback=True,
            fallback_url="",
            server_method="wsgiref",
            verbosity=0,
            log_stream=None,
        )
        app = app_from_config(config)
        app = setup_routes_from_config(app, config)

        self._server, self.port = _make_server_on_free_port(app)
        self.server_url = "http://localhost:{port}".format(port=self.port)
        self.auth_url = "http://{user}:{passwd}@localhost:{port}".format(
            user=self.username,
            passwd=self.password,
            port=self.port,
        )

        self._thread = threading.Thread(target=self._server.serve_forever)
        self._thread.daemon = True
        self._thread.start()

        interval = 0.1
        wait_seconds = 40
        for _ in range(int(wait_seconds / interval)):
            try:
                req = Request(self.server_url)
                with urlopen(req, timeout=1) as response:
                    if response.status in (200, 401):
                        break
            except (URLError, OSError):
                pass
            time.sleep(interval)
        else:
            raise RuntimeError(
                "Could not start the server, waited for {}s".format(wait_seconds)
            )

        # Set a default value for UV_EXTRA_INDEX_URL in the bazel env so that
        # the workspace .bazelrc `--action_env=UV_EXTRA_INDEX_URL` doesn't
        # fail on Windows when the variable is unset in the client env.
        self.bazel_env.setdefault("UV_EXTRA_INDEX_URL", "")

        # Use a sandbox-local credential store so credentials don't leak
        # to the host system.
        self.creds_dir = self.repo_root / ".uv-creds"
        self.creds_dir.mkdir(parents=True, exist_ok=True)
        self.bazel_env["UV_CREDENTIALS_DIR"] = str(self.creds_dir)

        # Log in to uv's credential store so `uv auth helper` can later
        # serve the credentials to Bazel or uv itself.
        self.run_bazel(
            "run",
            "//:uv",
            "--",
            "auth",
            "login",
            f"--username={self.username}",
            f"--password={self.password}",
            self.server_url,
        )

    def tearDown(self):
        # Clear credentials from uv's credential store to ensure we are not
        # logged into the service after the test.
        self.run_bazel(
            "run",
            "//:uv",
            "--",
            "auth",
            "logout",
            self.server_url,
            check=False,
        )
        self._server.shutdown()

    def _assert_server_requires_auth(self):
        req = Request(self.server_url + "/my-local-pkg/")
        try:
            urlopen(req, timeout=5)
            self.fail("Expected 401 without auth")
        except URLError:
            pass

    def _auth_header(self):
        return "Basic " + base64.b64encode(
            "{user}:{passwd}".format(
                user=self.username,
                passwd=self.password,
            ).encode("utf-8")
        ).decode("utf-8")

    def _assert_simple_api_sha256(self):
        auth_header = self._auth_header()
        req = Request(self.server_url + "/simple/my-local-pkg/")
        req.add_header("Authorization", auth_header)
        resp = urlopen(req, timeout=5)
        html = resp.read().decode("utf-8")

        match = re.search(r"#sha256=([a-f0-9]+)", html)
        self.assertIsNotNone(match, "No sha256 found in simple API: {}".format(html))
        pypiserver_sha256 = match.group(1)
        disk_sha256 = hashlib.sha256(self.wheel_path.read_bytes()).hexdigest()
        self.assertEqual(
            pypiserver_sha256,
            disk_sha256,
            "pypiserver hash {} != disk hash {}".format(pypiserver_sha256, disk_sha256),
        )

    def _creds_auth_args(self):
        return [
            "--strategy=PyRequirementsLockUv=local",
            "--action_env={key}={value}".format(
                key="UV_CREDENTIALS_DIR",
                value=str(self.creds_dir),
            ),
            "--action_env={key}={value}".format(
                key="UV_EXTRA_INDEX_URL",
                value=self.server_url,
            ),
        ]

    def _assert_lock_file(self, result):
        self.assertEqual(
            result.exit_code,
            0,
            "Lock update failed:\n{}".format(result.describe()),
        )
        lock_file = self.repo_root / "requirements.txt"
        self.assertTrue(lock_file.exists(), "Lock file was not created")
        contents = lock_file.read_text()
        self.assertIn("my-local-pkg", contents)
        self.assertIn("--hash=sha256:", contents)

    def test_lock_update_with_custom_index(self):
        self._assert_server_requires_auth()
        self._assert_simple_api_sha256()

        result = self.run_bazel(
            "run",
            "--action_env={key}={value}".format(
                key="UV_EXTRA_INDEX_URL",
                value=self.auth_url,
            ),
            "//:requirements.update",
        )
        self._assert_lock_file(result)

    def test_update_with_credential_helper(self):
        """Use a credential helper for authentication."""
        self._assert_server_requires_auth()
        result = self.run_bazel(
            "run",
            *self._creds_auth_args(),
            "//:requirements.update",
        )
        self._assert_lock_file(result)

    def test_update_with_uv_auth_helper(self):
        """Use the uv auth helper for authentication."""
        self._assert_server_requires_auth()
        result = self.run_bazel(
            "run",
            *self._creds_auth_args(),
            "//:requirements.update",
        )
        self._assert_lock_file(result)

    def test_diff_test_with_requirements(self):
        """Verify that ``diff_test`` can verify the generated lock file."""
        self._assert_server_requires_auth()

        # First generate the lock file
        result = self.run_bazel(
            "run",
            *self._creds_auth_args(),
            "//:requirements.update",
        )
        self._assert_lock_file(result)

        # Copy the generated lock file to the expected location. The inner
        # Bazel workspace is writable because it is a temporary copy created
        # by the integration test framework.
        generated = self.repo_root / "requirements.txt"
        expected = self.repo_root / "requirements_expected.txt"
        expected.write_text(generated.read_text())

        # Run the diff_test: it builds the lock action, then compares the
        # output to our expected file.
        result = self.run_bazel(
            "test",
            *self._creds_auth_args(),
            "//:requirements_diff_test",
        )
        self.assertEqual(
            result.exit_code,
            0,
            "diff_test failed:\n{}".format(result.describe()),
        )

    def test_no_existing_requirements(self):
        """Verify that ``bazel run`` and ``diff_test`` work when
        ``requirements.txt`` does not yet exist."""
        self._assert_server_requires_auth()

        # Remove the existing lock file to simulate a fresh checkout
        existing = self.repo_root / "requirements.txt"
        existing.unlink()
        self.assertFalse(existing.exists())

        # Run ``requirements.update`` to generate the lock from scratch.  The
        # underlying lock rule will have no ``existing_output`` to copy, but
        # ``uv pip compile`` should still produce the output.
        result = self.run_bazel(
            "run",
            *self._creds_auth_args(),
            "//:requirements.update",
        )
        self._assert_lock_file(result)

        # diff_test should pass now that ``requirements.txt`` exists again
        result = self.run_bazel(
            "test",
            *self._creds_auth_args(),
            "//:requirements_diff_test",
        )
        self.assertEqual(
            result.exit_code,
            0,
            "diff_test failed:\n{}".format(result.describe()),
        )


if __name__ == "__main__":
    unittest.main()

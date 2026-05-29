import base64
import hashlib
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
from wsgiref.simple_server import make_server

from pypiserver import app_from_config, setup_routes_from_config
from pypiserver.config import Config

from tests.integration import runner


def find_free_port():
    with closing(socket.socket(socket.AF_INET, socket.SOCK_STREAM)) as s:
        s.bind(("", 0))
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        return s.getsockname()[1]


def _create_wheel_bytes(name, version):
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


class UvLockIntegrationTest(runner.TestCase):
    def setUp(self):
        super().setUp()

        self.port = find_free_port()
        self.username = "testuser"
        self.password = "secretpass"
        self.server_url = "http://localhost:{port}".format(port=self.port)
        self.auth_url = "http://{user}:{passwd}@localhost:{port}".format(
            user=self.username,
            passwd=self.password,
            port=self.port,
        )

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
            port=self.port,
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

        self._server = make_server("localhost", self.port, app)
        self._thread = threading.Thread(target=self._server.serve_forever)
        self._thread.daemon = True
        self._thread.start()

        interval = 0.1
        wait_seconds = 40
        for _ in range(int(wait_seconds / interval)):
            try:
                req = Request(self.server_url)
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

    def tearDown(self):
        self._server.shutdown()

    def test_lock_update_with_custom_index(self):
        req = Request(self.server_url + "/my-local-pkg/")
        try:
            urlopen(req, timeout=5)
            self.fail("Expected 401 without auth")
        except URLError:
            pass

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

        simple_req = Request(self.server_url + "/simple/my-local-pkg/")
        simple_req.add_header("Authorization", auth_header)
        simple_resp = urlopen(simple_req, timeout=5)
        simple_html = simple_resp.read().decode("utf-8")
        import re

        hash_match = re.search(r"#sha256=([a-f0-9]+)", simple_html)
        self.assertIsNotNone(
            hash_match, "No sha256 found in simple API: {}".format(simple_html)
        )
        pypiserver_sha256 = hash_match.group(1)
        disk_sha256 = hashlib.sha256(self.wheel_path.read_bytes()).hexdigest()
        self.assertEqual(
            pypiserver_sha256,
            disk_sha256,
            "pypiserver hash {} != disk hash {}".format(pypiserver_sha256, disk_sha256),
        )

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

        lock_file = self.repo_root / "requirements.txt"
        self.assertTrue(lock_file.exists(), "Lock file was not created")
        contents = lock_file.read_text()
        self.assertIn("my-local-pkg", contents)
        self.assertIn(self.wheel_sha256, contents)

    def test_update_with_credential_helper(self):
        req = Request(self.server_url + "/my-local-pkg/")
        try:
            urlopen(req, timeout=5)
            self.fail("Expected 401 without auth")
        except URLError:
            pass

        cred_helper = self.dir / "cred_helper.sh"
        auth_header = "Basic " + base64.b64encode(
            "{user}:{passwd}".format(
                user=self.username,
                passwd=self.password,
            ).encode("utf-8")
        ).decode("utf-8")
        cred_helper.write_text(
            "#!/bin/bash\n"
            'echo \'{{"headers": {{"Authorization": ["{auth}"]}}}}\'\n'.format(
                auth=auth_header,
            )
        )
        cred_helper.chmod(0o755)

        result = self.run_bazel(
            "run",
            "--sandbox_add_mount_pair={source}={target}".format(
                source=cred_helper,
                target="/cred_helper.sh",
            ),
            "--action_env={key}={value}".format(
                key="UV_EXTRA_INDEX_URL",
                value=self.server_url,
            ),
            "--action_env={key}={value}".format(
                key="UV_CREDENTIAL_HELPER",
                value="/cred_helper.sh",
            ),
            "//:requirements.update",
        )
        self.assertEqual(
            result.exit_code,
            0,
            "Lock update failed:\n{}".format(result.describe()),
        )

        lock_file = self.repo_root / "requirements.txt"
        self.assertTrue(lock_file.exists(), "Lock file was not created")
        contents = lock_file.read_text()
        self.assertIn("my-local-pkg", contents)
        self.assertIn(self.wheel_sha256, contents)


if __name__ == "__main__":
    unittest.main()

import argparse
import hashlib
import io
import os
import sys
import uuid
import zipfile
from wsgiref.simple_server import make_server

from pypiserver import app_from_config, setup_routes_from_config
from pypiserver.config import Config


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


def main():
    parser = argparse.ArgumentParser(
        description="Standalone pypiserver for uv_lock integration tests"
    )
    parser.add_argument(
        "--packages-dir",
        type=str,
        default=None,
        help="Directory for the test wheels (default: $TEST_TMPDIR/pypi-server-packages)",
    )
    parser.add_argument(
        "--no-auth",
        action="store_true",
        default=False,
        help="Disable authentication (allows anonymous access)",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=0,
        help="Port to listen on (0 = find free port)",
    )
    parser.add_argument(
        "--host",
        default="localhost",
        help="Host to bind to",
    )
    args = parser.parse_args()

    if args.packages_dir is None:
        sandbox_root = (
            os.environ.get("TEST_TMPDIR") or os.environ.get("TMPDIR") or "/tmp"
        )
        args.packages_dir = os.path.join(sandbox_root, "pypi-server-packages")
    packages_dir = args.packages_dir
    os.makedirs(packages_dir, exist_ok=True)

    wheel_data, sha256, wheel_name = _create_wheel_bytes("my-local-pkg", "1.0.0")
    wheel_path = os.path.join(packages_dir, wheel_name)
    with open(wheel_path, "wb") as f:
        f.write(wheel_data)

    print("Wheel: {}".format(wheel_path), flush=True)
    print("SHA256: {}".format(sha256), flush=True)

    password = uuid.uuid4().hex
    username = "testuser"

    if args.no_auth:
        authenticate = []
    else:
        authenticate = ["download", "list", "update"]

    config = Config.default_with_overrides(
        roots=[packages_dir],
        port=args.port,
        host=args.host,
        authenticate=authenticate,
        password_file=None,
        auther=lambda u, p: u == username and p == password,
        disable_fallback=True,
        fallback_url="",
        server_method="wsgiref",
        verbosity=0,
        log_stream=None,
    )
    app = app_from_config(config)
    app = setup_routes_from_config(app, config)

    server = make_server(args.host, args.port, app)
    port = server.server_address[1]

    base_url = "http://{}:{}".format(args.host, port)
    auth_url = "http://{}:{}@{}:{}".format(username, password, args.host, port)

    print("\npypiserver listening on:\n", flush=True)
    print("  URL (no auth):  {}".format(base_url), flush=True)
    print("  URL (auth):     {}".format(auth_url), flush=True)
    print("\nRequired dependency in requirements.in:", flush=True)
    print("  my-local-pkg==1.0.0", flush=True)
    print("\nTo use from the uv_lock test workspace, run:", flush=True)
    print("  cd tests/integration/uv_lock", flush=True)
    print("  bazel run //:requirements.update \\", flush=True)
    print('    --action_env=UV_EXTRA_INDEX_URL="{}" \\'.format(auth_url), flush=True)
    print("    --action_env=UV_CREDENTIALS_DIR=<creds-dir>", flush=True)
    print("\nPress Ctrl+C to stop the server.\n", flush=True)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...", flush=True)
        server.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())

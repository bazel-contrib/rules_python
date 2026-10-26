"""Transform tool for testing py_wheel_transform."""

from __future__ import annotations

import os
import zipfile
from pathlib import Path


def main() -> None:
    in_whl = Path(os.environ["WHEEL_FILE"])
    out_dir = Path(os.environ["WHEEL_OUTPUT_ROOT"])
    marker = Path(os.environ["DATA_MARKER_FILE"]).read_text(encoding="utf-8").strip()
    out_whl = out_dir / in_whl.name

    with zipfile.ZipFile(in_whl, "r") as zin, zipfile.ZipFile(out_whl, "w") as zout:
        for item in zin.infolist():
            data = zin.read(item.filename)
            if item.filename == "demo_pkg/__init__.py":
                text = data.decode("utf-8").replace(
                    "TRANSFORMED = False", f'TRANSFORMED = "{marker}"'
                )
                data = text.encode("utf-8")
            zout.writestr(item, data)


if __name__ == "__main__":
    main()

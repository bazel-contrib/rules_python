import encodings
import json
import sys
from pathlib import Path

data = {
    "has_encodings": bool(encodings),
    "status": "ok",
}
Path(sys.argv[1]).write_text(
    json.dumps(data, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)

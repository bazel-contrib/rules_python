"""Helper functions for managing release tracking issues and checklists."""

import re

RELEASE_TITLE_RE = re.compile(r"Release (\d+\.\d+\.\d+)", re.IGNORECASE)


def parse_metadata_line(line):
    """Parses a checklist line with optional | key=value metadata."""
    match = re.match(r"^\s*-\s*\[([ xX])\]\s+([^|]+)(?:\s*\|\s*(.*))?$", line)
    if not match:
        return None

    checked = match.group(1).lower() == "x"
    name = match.group(2).strip()
    metadata_str = match.group(3)

    metadata = {}
    if metadata_str:
        pairs = metadata_str.strip().split()
        for pair in pairs:
            if "=" in pair:
                k, v = pair.split("=", 1)
                metadata[k] = v

    return {
        "checked": checked,
        "name": name,
        "metadata": metadata,
        "original_line": line,
    }


def format_metadata_line(checked, name, metadata):
    """Formats a checklist line with space-separated key=value metadata."""
    check_str = "x" if checked else " "
    if not metadata:
        return f"- [{check_str}] {name}"

    metadata_str = " ".join(f"{k}={v}" for k, v in metadata.items())
    return f"- [{check_str}] {name} | {metadata_str}"


def update_task_in_body(body, task_name, checked, metadata):
    """Updates a specific task's checked state and metadata in the issue body."""
    lines = body.splitlines()
    updated_lines = []
    found = False

    for line in lines:
        parsed = parse_metadata_line(line)
        if parsed and parsed["name"].lower() == task_name.lower():
            updated_lines.append(format_metadata_line(checked, task_name, metadata))
            found = True
        else:
            updated_lines.append(line)

    if not found:
        raise ValueError(
            f"Task '{task_name}' not found in issue body. "
            f"Expected format: '- [ ] {task_name}' or '- [x] {task_name}' (optionally followed by '| key=value')"
        )

    return "\n".join(updated_lines)


def parse_checklist_state(body):
    """Parses the main checklist tasks and their metadata."""
    state = {
        "prepare_release": {
            "checked": False,
            "status": None,
            "pr": None,
            "commit": None,
        },
        "create_branch": {
            "checked": False,
            "status": None,
            "branch": None,
            "commit": None,
        },
        "tag_final": {"checked": False, "status": None, "tag": None, "commit": None},
        "rc_tags": {},  # Dynamically mapped: int -> metadata dict
    }

    lines = body.splitlines()
    for line in lines:
        parsed = parse_metadata_line(line)
        if not parsed:
            continue

        name = parsed["name"].strip()
        meta = parsed["metadata"]
        checked = parsed["checked"]
        name_lower = name.lower()

        if "prepare release" in name_lower:
            state["prepare_release"] = {
                "checked": checked,
                "status": meta.get("status"),
                "pr": meta.get("pr"),
                "commit": meta.get("commit"),
            }
        elif "create release branch" in name_lower:
            state["create_branch"] = {
                "checked": checked,
                "status": meta.get("status"),
                "branch": meta.get("branch"),
                "commit": meta.get("commit"),
            }
        elif "tag final" in name_lower:
            state["tag_final"] = {
                "checked": checked,
                "status": meta.get("status"),
                "tag": meta.get("tag"),
                "commit": meta.get("commit"),
            }
        else:
            # Match Tag RC<num>
            rc_match = re.match(r"Tag RC(\d+)", name, re.IGNORECASE)
            if rc_match:
                rc_num = int(rc_match.group(1))
                state["rc_tags"][rc_num] = {
                    "checked": checked,
                    "status": meta.get("status"),
                    "tag": meta.get("tag"),
                    "commit": meta.get("commit"),
                }

    return state


def parse_backports(body):
    """Parses the ## Backports checklist section."""
    body = body.replace("\r\n", "\n")
    match = re.search(
        r"## Backports\n(.*?)(?=\n##|\n---|\Z)", body, re.DOTALL | re.IGNORECASE
    )
    if not match:
        return []

    section_content = match.group(1)
    items = []
    lines = section_content.splitlines()

    for line in lines:
        parsed = parse_metadata_line(line)
        if parsed:
            items.append(
                {
                    "pr_ref": parsed["name"],
                    "checked": parsed["checked"],
                    "status": parsed["metadata"].get("status", "PENDING"),
                    "rc": parsed["metadata"].get("rc"),
                    "commit": parsed["metadata"].get("commit"),
                    "metadata": parsed["metadata"],
                }
            )
    return items

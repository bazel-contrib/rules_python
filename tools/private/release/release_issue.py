"""Helper functions for managing release tracking issues and checklists."""

import re


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

import re


class BackportTask:
    """Represents a backport task from the tracking issue checklist."""

    def __init__(
        self,
        pr_ref: str,
        checked: bool,
        status: str,
        rc: str | None = None,
        commit: str | None = None,
        metadata: dict[str, str] | None = None,
    ):
        """Initializes a BackportTask.

        Args:
            pr_ref: The PR reference (e.g. '#123').
            checked: Whether the checklist item is checked.
            status: The status of the backport (e.g. 'pending', 'done',
                'error-merge-conflict').
            rc: The release candidate version this PR was backported to.
            commit: The cherry-pick commit SHA.
            metadata: Raw metadata parsed from the checklist line.
        """
        self.pr_ref = pr_ref
        self.checked = checked
        self.status = status
        self.rc = rc
        self.commit = commit
        self.metadata = metadata or {}

    def __repr__(self):
        return (
            f"BackportTask(pr_ref={self.pr_ref!r}, checked={self.checked!r}, "
            f"status={self.status!r}, rc={self.rc!r}, commit={self.commit!r})"
        )


class ReleaseTask:
    """Represents a release task from the tracking issue checklist."""

    def __init__(
        self,
        name: str,
        checked: bool,
        status: str | None = None,
        pr: str | None = None,
        commit: str | None = None,
        branch: str | None = None,
        tag: str | None = None,
        metadata: dict[str, str] | None = None,
    ):
        """Initializes a ReleaseTask.

        Args:
            name: The name of the task (e.g. 'Prepare Release').
            checked: Whether the checklist item is checked.
            status: The status of the task (e.g. 'pending', 'done').
            pr: The associated PR reference (e.g. '#123').
            commit: The associated commit SHA.
            branch: The associated branch name.
            tag: The associated tag name.
            metadata: Raw metadata parsed from the checklist line.
        """
        self.name = name
        self.checked = checked
        self.status = status
        self.pr = pr
        self.commit = commit
        self.branch = branch
        self.tag = tag
        self.metadata = metadata or {}

    def __repr__(self):
        return (
            f"ReleaseTask(name={self.name!r}, checked={self.checked!r}, "
            f"status={self.status!r}, pr={self.pr!r}, commit={self.commit!r}, "
            f"branch={self.branch!r}, tag={self.tag!r})"
        )


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
        for k, v in re.findall(r"(\w+)\s*=\s*(\S+)", metadata_str):
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

    metadata_pairs = []
    for k, v in metadata.items():
        if k == "commit" or k.endswith("_commit"):
            # The 'commit' key (and keys ending with '_commit') is special-cased with
            # a space after '=' so that GitHub autolinks the commit SHA. Autolinking
            # requires certain characters to precede the value.
            metadata_pairs.append(f"{k}= {v}")
        else:
            metadata_pairs.append(f"{k}={v}")
    metadata_str = " ".join(metadata_pairs)
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
    """Parses the main checklist tasks and their metadata.

    Returns:
        A dict containing ReleaseTask objects for 'prepare_release',
        'create_branch', 'tag_final', and a dict of RC tags.
    """
    state = {
        "prepare_release": ReleaseTask("Prepare Release", False),
        "create_branch": ReleaseTask("Create Release branch", False),
        "tag_final": ReleaseTask("Tag Final", False),
        "rc_tags": {},  # Dynamically mapped: int -> ReleaseTask
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
            state["prepare_release"] = ReleaseTask(
                name=name,
                checked=checked,
                status=meta.get("status"),
                pr=meta.get("pr"),
                commit=meta.get("commit"),
                metadata=meta,
            )
        elif "create release branch" in name_lower:
            state["create_branch"] = ReleaseTask(
                name=name,
                checked=checked,
                status=meta.get("status"),
                branch=meta.get("branch"),
                commit=meta.get("commit"),
                metadata=meta,
            )
        elif "tag final" in name_lower:
            state["tag_final"] = ReleaseTask(
                name=name,
                checked=checked,
                status=meta.get("status"),
                tag=meta.get("tag"),
                commit=meta.get("commit"),
                metadata=meta,
            )
        else:
            # Match Tag RC<num>
            rc_match = re.match(r"Tag RC(\d+)", name, re.IGNORECASE)
            if rc_match:
                rc_num = int(rc_match.group(1))
                state["rc_tags"][rc_num] = ReleaseTask(
                    name=name,
                    checked=checked,
                    status=meta.get("status"),
                    tag=meta.get("tag"),
                    commit=meta.get("commit"),
                    metadata=meta,
                )

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
                BackportTask(
                    pr_ref=parsed["name"],
                    checked=parsed["checked"],
                    status=parsed["metadata"].get("status", "pending"),
                    rc=parsed["metadata"].get("rc"),
                    commit=parsed["metadata"].get("commit"),
                    metadata=parsed["metadata"],
                )
            )
    return items


def add_backports_to_body(body: str, items: list[dict]) -> str:
    """Adds new backport checklist items to the ## Backports section.

    Args:
        body: The issue body.
        items: A list of dicts, where each dict has a 'ref' key (str) and
               optional 'metadata' key (dict).
    """
    body = body.replace("\r\n", "\n")
    # Find the Backports section
    pattern = r"(## Backports\n)(.*?)(?=\n##|\n---|\Z)"
    match = re.search(pattern, body, re.DOTALL | re.IGNORECASE)
    if not match:
        raise ValueError("Could not find '## Backports' section in issue body.")

    section_content = match.group(2)

    # Parse existing backports to avoid duplicates
    existing_items = parse_backports(body)
    existing_refs = {item.pr_ref for item in existing_items}

    new_lines = []
    for item in items:
        ref = item["ref"]
        # Normalize numeric refs to #numeric
        if not ref.startswith("#") and ref.isdigit():
            ref = f"#{ref}"

        if ref in existing_refs:
            print(f"PR {ref} is already in the backports list. Skipping.")
            continue
        existing_refs.add(ref)

        metadata = item.get("metadata", {})
        new_lines.append(
            format_metadata_line(checked=False, name=ref, metadata=metadata)
        )

    if not new_lines:
        return body

    # Append new lines to the section content.
    section_content_clean = section_content.rstrip("\n")
    separator = "\n" if section_content_clean else ""
    updated_section = section_content_clean + separator + "\n".join(new_lines) + "\n\n"

    # Replace the old section with the updated one
    start, end = match.span(2)
    return body[:start] + updated_section + body[end:]


def add_rc_task_to_body(body: str, rc_num: int) -> str:
    """Adds a new 'Tag RC<rc_num>' task to the checklist in the issue body."""
    body = body.replace("\r\n", "\n")
    lines = body.splitlines()

    # Find the index of the last "Tag RC<M>" line
    last_rc_idx = -1
    for i, line in enumerate(lines):
        parsed = parse_metadata_line(line)
        if parsed and re.match(r"Tag RC\d+", parsed["name"], re.IGNORECASE):
            last_rc_idx = i

    if last_rc_idx == -1:
        # If no RC task found (unexpected, but fallback to before "Tag Final")
        for i, line in enumerate(lines):
            parsed = parse_metadata_line(line)
            if parsed and parsed["name"].lower() == "tag final":
                last_rc_idx = i - 1
                break

    if last_rc_idx == -1:
        raise ValueError("Could not find a place to insert the new RC task.")

    new_task_line = f"- [ ] Tag RC{rc_num}"
    lines.insert(last_rc_idx + 1, new_task_line)

    return "\n".join(lines)

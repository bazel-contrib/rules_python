"""Utility functions for handling news entries and merging them into CHANGELOG.md."""

import pathlib
import re


def _get_sub_category(content):
    """Extracts the sub-category in parentheses from the entry content."""
    match = re.match(r"^(?:\*|-)\s*\(([^)]+)\)", content)
    if match:
        return match.group(1).lower()
    return ""


def is_news_file(path):
    """Checks if a file path is a valid news file."""
    path = pathlib.Path(path)
    if not path.is_file():
        return False
    if path.suffix != ".md":
        return False
    parts = path.name.split(".")
    if len(parts) < 3:
        return False
    return True


def _get_news_files(news_dir):
    """Returns a list of news files matching the <id>.<category>.md pattern."""
    news_path = pathlib.Path(news_dir)
    if not news_path.exists():
        return []

    return [p for p in news_path.iterdir() if is_news_file(p)]


def _parse_new_files(news_files):
    """Parses news files and groups them by category."""
    entries = {}
    for p in news_files:
        if not is_news_file(p):
            continue
        parts = p.name.split(".")
        category = parts[1].lower()

        content = p.read_text(encoding="utf-8").strip()

        if not content:
            continue

        # Format as list item if not already
        if not (content.startswith("* ") or content.startswith("- ")):
            content = f"* {content}"

        if category not in entries:
            entries[category] = []
        entries[category].append(content)

    return entries


def generate_release_block(version, release_date, news_entries):
    """Generates the markdown block for the release."""
    header_version = version.replace(".", "-")
    lines = [
        f"{{#v{header_version}}}",
        f"## [{version}] - {release_date}",
        "",
        f"[{version}]: https://github.com/bazel-contrib/rules_python/releases/tag/{version}",
        "",
    ]

    # Standard categories in preferred order
    category_order = ["removed", "changed", "fixed", "added"]
    # Add any other categories found
    for cat in news_entries:
        if cat not in category_order:
            category_order.append(cat)

    for cat in category_order:
        if cat in news_entries and news_entries[cat]:
            lines.append(f"{{#v{header_version}-{cat}}}")
            lines.append(f"### {cat.capitalize()}")

            # Sort entries by sub-category, then by content
            sorted_entries = sorted(
                news_entries[cat], key=lambda e: (_get_sub_category(e), e)
            )

            for entry in sorted_entries:
                lines.append(entry)
            lines.append("")

    return "\n".join(lines)


def _add_news_to_changelog(input_path, output_path, version, entries, release_date):
    """Adds or merges news entries into CHANGELOG.md."""
    input_path = pathlib.Path(input_path)
    output_path = pathlib.Path(output_path)
    changelog_content = input_path.read_text(encoding="utf-8")

    if version == "unreleased":
        header_version = "unreleased"
        version_anchor = "{#unreleased}"
        category_anchor_fmt = "{{#unreleased-{cat}}}"
        category_anchor_pattern = r"\{#unreleased-(?P<cat>[a-z]+)\}"
    else:
        header_version = version.replace(".", "-")
        version_anchor = f"{{#v{header_version}}}"
        category_anchor_fmt = "{{#v" + header_version + "-{cat}}}"
        category_anchor_pattern = (
            r"\{#v" + re.escape(header_version) + r"-(?P<cat>[a-z]+)\}"
        )

    # Safety fix for duplicate anchors (like {#v0-0-0} in template vs active)
    # We split the file by the template end marker if it exists, and only search/replace in the post-template part.
    template_end = re.search(r"END_UNRELEASED_TEMPLATE\s*\n-->", changelog_content)
    if template_end:
        pre_content = changelog_content[: template_end.end()]
        post_content = changelog_content[template_end.end() :]
    else:
        pre_content = ""
        post_content = changelog_content

    version_exists = version_anchor in post_content

    if version_exists:
        if not entries and version != "unreleased":
            print(
                f"Version {version} already exists and no news entries found"
                " to merge. Doing nothing."
            )
            output_path.write_text(changelog_content, encoding="utf-8")
            return

        print(f"Version {version} already exists in changelog. Merging news entries...")
        # Extract the existing version block from post_content
        pattern = (
            r"(?P<anchor>"
            + re.escape(version_anchor)
            + r")(?P<content>.*?)(?=\n\s*\{#v(?!0-0-0)\d+-\d+-\d+\}|\Z)"
        )
        match = re.search(pattern, post_content, re.DOTALL)
        if not match:
            raise RuntimeError(
                f"Could not find content for existing version {version} in CHANGELOG.md"
            )

        content_block = match.group("content")

        # Strip the "Unreleased changes..." sentence for Unreleased preview
        if version == "unreleased":
            content_block = re.sub(
                r"Unreleased\s+changes\s+are\s+tracked\s+as\s+individual\s+files\s+in\s+the\s+\[news/\]\(\./news\)\s+directory,\s+or\s+view\s+the\s+\[latest\s+generated\s+changelog\]\(https://rules-python\.readthedocs\.io/en/latest/changelog\.html\)\.\s*\n*",
                "",
                content_block,
            )

        # category_anchor_pattern is defined at the top
        match_cat = re.search(category_anchor_pattern, content_block)
        if match_cat:
            header_end_idx = match_cat.start()
            header_str = content_block[:header_end_idx]
            categories_str = content_block[header_end_idx:]
        else:
            header_str = content_block
            categories_str = ""

        # Parse existing categories
        existing_entries = {}
        if categories_str:
            cat_matches = list(re.finditer(category_anchor_pattern, categories_str))
            for i, m in enumerate(cat_matches):
                cat = m.group("cat")
                start_idx = m.end()
                end_idx = (
                    cat_matches[i + 1].start()
                    if i + 1 < len(cat_matches)
                    else len(categories_str)
                )
                cat_content = categories_str[start_idx:end_idx].strip()

                lines = cat_content.splitlines()
                cat_entries = []
                current_entry = []
                for line in lines:
                    if not line.strip() or line.strip().startswith("### "):
                        continue
                    if line.startswith("* ") or line.startswith("- "):
                        if current_entry:
                            cat_entries.append("\n".join(current_entry))
                        current_entry = [line]
                    else:
                        if current_entry:
                            current_entry.append(line)
                if current_entry:
                    cat_entries.append("\n".join(current_entry))
                existing_entries[cat] = cat_entries

        # Merge news entries
        merged_entries = dict(existing_entries)
        for cat, cat_entries in entries.items():
            if cat not in merged_entries:
                merged_entries[cat] = []
            merged_entries[cat].extend(cat_entries)

        # Reconstruct categories
        reconstructed_lines = []
        category_order = ["removed", "changed", "fixed", "added"]
        for cat in merged_entries:
            if cat not in category_order:
                category_order.append(cat)

        for cat in category_order:
            if cat in merged_entries and merged_entries[cat]:
                reconstructed_lines.append(category_anchor_fmt.format(cat=cat))
                reconstructed_lines.append(f"### {cat.capitalize()}")

                sorted_entries = sorted(
                    merged_entries[cat], key=lambda e: (_get_sub_category(e), e)
                )

                for entry in sorted_entries:
                    reconstructed_lines.append(entry)
                reconstructed_lines.append("")

        new_categories_str = "\n".join(reconstructed_lines)
        new_release_block = (
            header_str.rstrip() + "\n\n" + new_categories_str.strip() + "\n"
        )
        if version == "unreleased" and not new_categories_str.strip():
            new_release_block = (
                header_str.rstrip() + "\n\nNo notable unreleased changes.\n"
            )

        # Replace in post_content
        new_post_content = re.sub(
            pattern,
            r"\g<anchor>\n" + new_release_block.strip() + "\n",
            post_content,
            flags=re.DOTALL,
        )
        output_path.write_text(pre_content + new_post_content, encoding="utf-8")

    else:
        if entries:
            print(
                f"Version {version} does not exist in changelog. Creating new"
                " release section from news entries..."
            )
            # Extract template
            template_match = re.search(
                r"BEGIN_UNRELEASED_TEMPLATE\s*\n(.*?)\n\s*END_UNRELEASED_TEMPLATE",
                changelog_content,
                re.DOTALL,
            )
            if not template_match:
                raise RuntimeError(
                    "Could not find BEGIN_UNRELEASED_TEMPLATE in CHANGELOG.md"
                )

            unreleased_template = template_match.group(1).strip()
            new_release_block = generate_release_block(version, release_date, entries)

            replacement = f"{unreleased_template}\n\n{new_release_block}\n"

            # Replace the active Unreleased section
            pattern = r"(END_UNRELEASED_TEMPLATE\s*\n-->\s*\n)(.*?)(\n\s*\{#v(?!0-0-0)\d+-\d+-\d+\})"

            if not re.search(pattern, changelog_content, re.DOTALL):
                raise RuntimeError(
                    "Could not find active Unreleased section to replace in"
                    " CHANGELOG.md"
                )

            new_content = re.sub(
                pattern,
                r"\g<1>" + replacement + r"\g<3>",
                changelog_content,
                flags=re.DOTALL,
            )
            output_path.write_text(new_content, encoding="utf-8")
        else:
            # Fallback to old behavior
            print(
                f"No news entries found and version {version} does not exist."
                " Falling back to manual changelog update..."
            )
            header_version = version.replace(".", "-")
            lines = changelog_content.splitlines()

            new_lines = []
            after_template = False
            before_already_released = True
            for line in lines:
                if "END_UNRELEASED_TEMPLATE" in line:
                    after_template = True
                if re.match("#v[1-9]-", line):
                    before_already_released = False

                if after_template and before_already_released:
                    line = line.replace(
                        "## Unreleased", f"## [{version}] - {release_date}"
                    )
                    line = line.replace("{#unreleased-", f"{{#v{header_version}-")
                    line = line.replace("{#unreleased}", f"{{#v{header_version}}}")
                    line = line.replace("unreleased", version)

                new_lines.append(line)

            output_path.write_text("\n".join(new_lines), encoding="utf-8")


def merge_new_into_changelog(
    changelog_path,
    output_path,
    news_dir,
    version,
    release_date,
    delete_news=False,
):
    """Merges news entries from news_dir into changelog_path and writes to output_path."""
    news_files = _get_news_files(news_dir)
    entries = _parse_new_files(news_files)
    _add_news_to_changelog(
        input_path=changelog_path,
        output_path=output_path,
        version=version,
        entries=entries,
        release_date=release_date,
    )
    if delete_news:
        for p in news_files:
            p.unlink()
        if news_files:
            print(f"Removed {len(news_files)} processed news files.")


def update_changelog(
    version,
    release_date,
    changelog_path="CHANGELOG.md",
    output_path=None,
    news_dir="news",
    delete_news=True,
):
    """Performs the version replacements in CHANGELOG.md."""
    if output_path is None:
        output_path = changelog_path
    merge_new_into_changelog(
        changelog_path=changelog_path,
        output_path=output_path,
        news_dir=news_dir,
        version=version,
        release_date=release_date,
        delete_news=delete_news,
    )

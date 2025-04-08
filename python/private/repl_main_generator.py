import sys
import textwrap
from pathlib import Path

LINE_TO_REPLACE = """\
    pass # %REPLACE_WHOLE_LINE_WITH_STUB%
"""

def main(argv):
    template = Path(sys.argv[1])
    stub = Path(sys.argv[2])
    output = Path(sys.argv[3])

    template_text = template.read_text()
    stub_text = stub.read_text()

    indented_stub_text = textwrap.indent(stub_text, " " * 4)

    output_text = template_text.replace(LINE_TO_REPLACE, indented_stub_text)
    if template_text == output_text:
        raise ValueError("Failed to find the following in the template: {LINE_TO_REPLACE}")

    output.write_text(output_text)


if __name__ == "__main__":
    sys.exit(main(sys.argv))

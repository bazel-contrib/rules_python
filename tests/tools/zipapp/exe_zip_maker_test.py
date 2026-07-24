import hashlib
import stat

from tools.private.zipapp import exe_zip_maker


def test_create_exe_zip(tmp_path):
    preamble_path = tmp_path / "preamble.txt"
    zip_path = tmp_path / "data.zip"
    output_path = tmp_path / "output.exe"

    # Create dummy zip file
    zip_content = b"PK\x03\x04dummyzipcontent"
    zip_path.write_bytes(zip_content)

    # Calculate expected hash
    expected_hash = hashlib.sha256(zip_content).hexdigest().encode("utf-8")

    # Create preamble with placeholder
    preamble_text = b"#!/bin/bash\nEXPECTED_HASH='%ZIP_HASH%'\n# ... logic ...\n"
    preamble_path.write_bytes(preamble_text)

    # Call create_exe_zip directly
    exe_zip_maker.create_exe_zip(str(preamble_path), str(zip_path), str(output_path))

    # Verify output exists
    assert output_path.exists(), f"Output path '{output_path}' should exist"

    # Verify executable bit
    st = output_path.stat()
    assert st.st_mode & stat.S_IEXEC, (
        f"Output path '{output_path}' should be executable"
    )

    # Verify content
    content = output_path.read_bytes()

    # Split content back into preamble and zip
    # We know the preamble text length after substitution.
    expected_preamble = preamble_text.replace(b"%ZIP_HASH%", expected_hash)

    assert content.startswith(expected_preamble)
    assert content.endswith(zip_content), (
        "Output content should end with the zip content"
    )
    assert len(content) == len(expected_preamble) + len(zip_content)

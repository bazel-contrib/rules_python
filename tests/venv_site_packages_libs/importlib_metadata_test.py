import importlib.metadata
import pathlib
import sys


def test_importlib_metadata_files():
    files = importlib.metadata.files("whl-with-data1")
    assert files is not None, "importlib.metadata.files returned None"
    assert len(files) > 0, "importlib.metadata.files returned empty list"

    # Verify it contains expected files.
    # The RECORD file lists paths relative to the installation root
    # (site-packages).
    # Per PEP 376 and PEP 427:
    # - purelib and platlib files are installed directly under
    #   site-packages:
    #   whl_with_data1-1.0.data/purelib/data_overlap.py should be
    #   installed as data_overlap.py, and
    #   whl_with_data1-1.0.data/platlib/whl_with_data1/platlib_file.txt
    #   should be whl_with_data1/platlib_file.txt.
    # - scripts, headers, and data files installed outside site-packages
    #   are recorded relative to site-packages traversing up to the venv
    #   root (e.g. ../../../bin/ on POSIX, ../../Scripts/ on Windows).
    # - On Windows, venv bin scripts have a .bat extension appended.
    if sys.platform == "win32":
        scripts_prefix = "../../Scripts/"
        headers_prefix = "../../Include/"
        data_prefix = "../../"
        shebang_script_ext = ".bat"
    else:
        scripts_prefix = "../../../bin/"
        headers_prefix = "../../../include/"
        data_prefix = "../../../"
        shebang_script_ext = ""

    expected_paths = sorted(
        [
            scripts_prefix + "data_overlap.sh",
            data_prefix + "bin/data_overlap.sh",
            scripts_prefix + "overlap/both.sh",
            scripts_prefix + "overlap/script1.sh",
            scripts_prefix + "whl_script.sh",
            scripts_prefix + "whl_with_data1_script" + shebang_script_ext,
            headers_prefix + "data_overlap.h",
            data_prefix + "include/data_overlap.h",
            headers_prefix + "overlap/both.h",
            headers_prefix + "overlap/header1.h",
            headers_prefix + "whl_with_data1/header_file.h",
            data_prefix + "overlap/both.txt",
            data_prefix + "overlap/data1.txt",
            data_prefix + "site-packages/data_overlap.py",
            data_prefix + "whl_with_data1/data_data_file.txt",
            data_prefix + "whl_with_data1/data_data_file.txt",
            "data_overlap.py",
            "whl_with_data1/data_file.txt",
            "whl_with_data1/platlib_file.txt",
        ]
    )
    file_paths = sorted(str(f).replace("\\", "/") for f in files)
    assert file_paths == expected_paths

    for f in files:
        resolved = pathlib.Path(f.locate())
        assert resolved.exists(), f"Expected file {f} (resolved to {resolved}) to exist"
        assert resolved.is_file(), f"Expected {resolved} to be a regular file"

        # Verify file content can be read both as binary and as text
        content = f.read_binary()
        assert content is not None

        text = f.read_text(encoding="utf-8")
        assert text is not None

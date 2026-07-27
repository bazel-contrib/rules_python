import os
import shutil
import zipfile

from tools.private.zipapp import zipper


def symlink_target_path(p):
    return p.replace("/", os.sep)


def is_symlink(zip_info):
    # Check upper 4 bits of external_attr for S_IFLNK
    # S_IFLNK is 0o120000 = 0xA000
    attr = zip_info.external_attr >> 16
    return (attr & 0xF000) == 0xA000


def assert_zip_file_content(zf, path, content=None, is_symlink_file=False, target=None):
    info = zf.getinfo(path)
    if is_symlink_file:
        assert is_symlink(info), f"{path} should be a symlink but is not"
        assert zf.read(path).decode() == target
    else:
        assert not is_symlink(info), f"{path} should NOT be a symlink but is"
        assert zf.read(path).decode() == content


def create_zip(manifest_path, output_zip, **kwargs):
    defaults = {
        "manifest_path": manifest_path,
        "output_zip": output_zip,
        "compress_level": 0,
        "workspace_name": "my_ws",
        "legacy_external_runfiles": False,
        "runfiles_dir": "runfiles",
        "platform_pathsep": os.sep,
    }
    defaults.update(kwargs)
    zipper.create_zip(**defaults)


def extract_zip(zip_path, extract_dir):
    # Manually extract to preserve symlinks
    with zipfile.ZipFile(zip_path, "r") as zf:
        for info in zf.infolist():
            extract_path = extract_dir / info.filename
            extract_path.parent.mkdir(parents=True, exist_ok=True)
            if is_symlink(info):
                target = zf.read(info).decode()
                os.symlink(target, extract_path)
            else:
                with zf.open(info) as src, open(extract_path, "wb") as dst:
                    shutil.copyfileobj(src, dst)


def test_create_zip_with_files_and_symlinks(tmp_path):
    manifest_path = tmp_path / "manifest.txt"
    output_zip = tmp_path / "output.zip"

    file1_path = tmp_path / "file1.txt"
    file1_path.write_text("content1")

    link_target_path = "target.txt"
    symlink_path = tmp_path / "symlink_source"
    symlink_path.symlink_to(link_target_path)

    manifest_content = [
        f"regular|0|file1.txt|{file1_path}",
        f"rf-file|0|foo/bar.txt|{file1_path}",
        f"rf-symlink|1|link1|{symlink_path}",
        f"rf-root-symlink|0|root_file|{file1_path}",
        "rf-empty|empty_file",
    ]
    manifest_path.write_text("\n".join(manifest_content))

    create_zip(manifest_path, output_zip)

    assert output_zip.exists()

    with zipfile.ZipFile(output_zip, "r") as zf:
        assert set(zf.namelist()) == {
            "file1.txt",
            "runfiles/my_ws/foo/bar.txt",
            "runfiles/my_ws/link1",
            "runfiles/root_file",
            "runfiles/my_ws/empty_file",
        }

        assert_zip_file_content(zf, "file1.txt", content="content1")
        assert_zip_file_content(zf, "runfiles/my_ws/foo/bar.txt", content="content1")
        assert_zip_file_content(
            zf, "runfiles/my_ws/link1", is_symlink_file=True, target="target.txt"
        )
        assert_zip_file_content(zf, "runfiles/root_file", content="content1")
        assert_zip_file_content(zf, "runfiles/my_ws/empty_file", content="")


def test_create_zip_with_direct_symlink(tmp_path):
    manifest_path = tmp_path / "manifest.txt"
    output_zip = tmp_path / "output.zip"

    manifest_content = ["symlink|path/to/link|target/path"]
    manifest_path.write_text("\n".join(manifest_content))

    create_zip(manifest_path, output_zip)

    with zipfile.ZipFile(output_zip, "r") as zf:
        assert zf.namelist() == ["runfiles/path/to/link"]
        assert_zip_file_content(
            zf,
            "runfiles/path/to/link",
            is_symlink_file=True,
            target=symlink_target_path("../../target/path"),
        )


def test_pathsep_normalization(tmp_path):
    manifest_path = tmp_path / "manifest.txt"
    output_zip = tmp_path / "output.zip"

    file1_path = tmp_path / "file1.txt"
    file1_path.write_text("content1")

    manifest_content = [
        f"regular|0|dir/file.txt|{file1_path}",
        "symlink|link/path|target/path",
    ]
    manifest_path.write_text("\n".join(manifest_content))

    create_zip(manifest_path, output_zip, platform_pathsep="\\")

    with zipfile.ZipFile(output_zip, "r") as zf:
        assert set(zf.namelist()) == {"dir/file.txt", "runfiles/link/path"}
        assert_zip_file_content(
            zf,
            "runfiles/link/path",
            is_symlink_file=True,
            target="..\\target\\path",
        )


def test_symlink_precedence(tmp_path):
    manifest_path = tmp_path / "manifest.txt"
    output_zip = tmp_path / "output.zip"

    file1_path = tmp_path / "file1.txt"
    file1_path.write_text("content1")

    manifest_content = [
        f"rf-file|0|path/to/file|{file1_path}",
        "symlink|my_ws/path/to/file|symlink/target",
    ]
    manifest_path.write_text("\n".join(manifest_content))

    create_zip(manifest_path, output_zip)

    with zipfile.ZipFile(output_zip, "r") as zf:
        assert zf.namelist() == ["runfiles/my_ws/path/to/file"]
        assert_zip_file_content(
            zf,
            "runfiles/my_ws/path/to/file",
            is_symlink_file=True,
            target=symlink_target_path("../../../symlink/target"),
        )


def test_timestamps_are_deterministic(tmp_path):
    manifest_path = tmp_path / "manifest.txt"
    output_zip = tmp_path / "output.zip"

    file1_path = tmp_path / "file1.txt"
    file1_path.write_text("content1")
    os.utime(file1_path, None)

    manifest_content = [f"regular|0|file1.txt|{file1_path}"]
    manifest_path.write_text("\n".join(manifest_content))

    create_zip(manifest_path, output_zip)

    with zipfile.ZipFile(output_zip, "r") as zf:
        info = zf.getinfo("file1.txt")
        expected_date_time = (1980, 1, 1, 0, 0, 0)
        assert info.date_time == expected_date_time


def test_runfiles_mapping_with_cross_repo_paths(tmp_path):
    manifest_path = tmp_path / "manifest.txt"
    output_zip = tmp_path / "output.zip"

    file1_path = tmp_path / "file1.txt"
    file1_path.write_text("content1")

    manifest_content = [
        f"rf-file|0|../other_repo/foo.txt|{file1_path}",
        "rf-empty|../other_repo/empty_file",
    ]
    manifest_path.write_text("\n".join(manifest_content))

    create_zip(manifest_path, output_zip, workspace_name="my_ws")

    with zipfile.ZipFile(output_zip, "r") as zf:
        assert set(zf.namelist()) == {
            "runfiles/other_repo/foo.txt",
            "runfiles/other_repo/empty_file",
        }
        assert_zip_file_content(zf, "runfiles/other_repo/foo.txt", content="content1")
        assert_zip_file_content(zf, "runfiles/other_repo/empty_file", content="")


def test_runfiles_mapping_with_legacy_external_paths(tmp_path):
    manifest_path = tmp_path / "manifest.txt"
    output_zip = tmp_path / "output.zip"

    file1_path = tmp_path / "file1.txt"
    file1_path.write_text("content1")

    manifest_content = [
        f"rf-file|0|external/other_repo/foo.txt|{file1_path}",
        "rf-empty|external/other_repo/empty_file",
    ]
    manifest_path.write_text("\n".join(manifest_content))

    create_zip(
        manifest_path, output_zip, workspace_name="my_ws", legacy_external_runfiles=True
    )

    with zipfile.ZipFile(output_zip, "r") as zf:
        assert set(zf.namelist()) == {
            "runfiles/other_repo/foo.txt",
            "runfiles/other_repo/empty_file",
        }
        assert_zip_file_content(zf, "runfiles/other_repo/foo.txt", content="content1")
        assert_zip_file_content(zf, "runfiles/other_repo/empty_file", content="")


def test_output_deterministic(tmp_path):
    manifest_path = tmp_path / "manifest.txt"
    output_zip = tmp_path / "output.zip"

    file1 = tmp_path / "file1"
    file1.write_text("1")
    file2 = tmp_path / "file2"
    file2.write_text("2")
    file3 = tmp_path / "file3"
    file3.write_text("3")

    manifest_content = [
        f"regular|0|z/regular|{file1}",
        f"rf-file|0|b_rf_file|{file2}",
        f"rf-root-symlink|0|a_root_link|{file3}",
        f"regular|0|a/regular|{file3}",
        "rf-empty|d_rf_empty",
        f"rf-symlink|0|c_rf_link|{file3}",
    ]

    manifest_path.write_text("\n".join(manifest_content))

    create_zip(manifest_path, output_zip, workspace_name="my_ws")

    with zipfile.ZipFile(output_zip, "r") as zf:
        assert zf.namelist() == [
            "a/regular",
            "runfiles/a_root_link",
            "runfiles/my_ws/b_rf_file",
            "runfiles/my_ws/c_rf_link",
            "runfiles/my_ws/d_rf_empty",
            "z/regular",
        ]


def test_symlink_extraction(tmp_path):
    manifest_path = tmp_path / "manifest.txt"
    output_zip = tmp_path / "output.zip"

    target_file = tmp_path / "target_file.txt"
    target_file.write_text("target content")

    manifest_content = [
        f"rf-file|0|target/path|{target_file}",
        "symlink|my_ws/path/to/link|my_ws/target/path",
        f"rf-file|0|same_dir_target|{target_file}",
        "symlink|my_ws/same_dir_link|my_ws/same_dir_target",
    ]
    manifest_path.write_text("\n".join(manifest_content))

    create_zip(manifest_path, output_zip, workspace_name="my_ws")

    extract_dir = tmp_path / "extract"
    extract_dir.mkdir()

    extract_zip(output_zip, extract_dir)

    link_path = extract_dir / "runfiles/my_ws/path/to/link"
    assert link_path.is_symlink(), f"{link_path} should be a symlink"
    assert os.readlink(link_path) == "../../target/path".replace("/", os.path.sep)
    assert link_path.read_text() == "target content"

    link2_path = extract_dir / "runfiles/my_ws/same_dir_link"
    assert link2_path.is_symlink(), f"{link2_path} should be a symlink"
    assert os.readlink(link2_path) == "same_dir_target"
    assert link2_path.read_text() == "target content"

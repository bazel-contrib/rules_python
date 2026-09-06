use std::env;
use std::fs;

use exe_zip_maker_lib::{
    compute_file_sha256_hex, create_exe_zip, replace_bytes, PLACEHOLDER,
};

#[test]
fn test_replace_bytes_none() {
    let src = b"hello world";
    assert_eq!(replace_bytes(src, b"foo", b"bar"), b"hello world");
}

#[test]
fn test_replace_bytes_single() {
    let src = b"EXPECTED_HASH='%ZIP_HASH%'";
    let replaced = replace_bytes(src, PLACEHOLDER, b"12345678");
    assert_eq!(replaced, b"EXPECTED_HASH='12345678'");
}

#[test]
fn test_replace_bytes_multiple() {
    let src = b"%ZIP_HASH% and %ZIP_HASH%";
    let replaced = replace_bytes(src, PLACEHOLDER, b"abc");
    assert_eq!(replaced, b"abc and abc");
}

#[test]
fn test_replace_bytes_empty_from() {
    let src = b"unchanged";
    assert_eq!(replace_bytes(src, b"", b"abc"), b"unchanged");
}

#[test]
fn test_compute_file_sha256_hex() {
    let temp_dir = env::temp_dir().join(format!("sha256_test_{}", std::process::id()));
    fs::create_dir_all(&temp_dir).unwrap();
    let file_path = temp_dir.join("sample.txt");

    fs::write(&file_path, b"hello world\n").unwrap();
    let hash = compute_file_sha256_hex(&file_path).unwrap();
    assert_eq!(
        hash,
        "a948904f2f0f479b8f8197694b30184b0d2ed1c1cd2a1ec0fb85d299a192a447"
    );

    let _ = fs::remove_dir_all(&temp_dir);
}

#[test]
fn test_create_exe_zip_successful() {
    let temp_dir = env::temp_dir().join(format!("create_exe_zip_test_{}", std::process::id()));
    fs::create_dir_all(&temp_dir).unwrap();

    let preamble_path = temp_dir.join("preamble.sh");
    let zip_path = temp_dir.join("data.zip");
    let output_path = temp_dir.join("output.exe");

    let zip_content = b"PK\x03\x04dummyzipcontent";
    fs::write(&zip_path, zip_content).unwrap();

    let preamble_text = b"#!/bin/bash\nEXPECTED_HASH='%ZIP_HASH%'\n# ... logic ...\n";
    fs::write(&preamble_path, preamble_text).unwrap();

    create_exe_zip(&preamble_path, &zip_path, &output_path).unwrap();

    assert!(output_path.exists());

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let st = fs::metadata(&output_path).unwrap();
        assert_ne!(
            st.permissions().mode() & 0o100,
            0,
            "Expected executable permission on output file"
        );
    }

    let content = fs::read(&output_path).unwrap();
    let expected_hash = "65e39989ca91c49484998aa3f0429f6943c029609bfd2f3c18c77bf9ded72c59";
    let expected_preamble = replace_bytes(preamble_text, PLACEHOLDER, expected_hash.as_bytes());

    assert!(content.starts_with(&expected_preamble));
    assert!(content.ends_with(zip_content));
    assert_eq!(content.len(), expected_preamble.len() + zip_content.len());

    let _ = fs::remove_dir_all(&temp_dir);
}

#[test]
fn test_create_exe_zip_multiple_placeholders() {
    let temp_dir = env::temp_dir().join(format!("create_exe_zip_multi_{}", std::process::id()));
    fs::create_dir_all(&temp_dir).unwrap();

    let preamble_path = temp_dir.join("preamble.sh");
    let zip_path = temp_dir.join("data.zip");
    let output_path = temp_dir.join("output.exe");

    let zip_content = b"PK\x03\x04dummyzipcontent";
    fs::write(&zip_path, zip_content).unwrap();

    let preamble_text = b"# First: %ZIP_HASH%\n# Second: %ZIP_HASH%\n";
    fs::write(&preamble_path, preamble_text).unwrap();

    create_exe_zip(&preamble_path, &zip_path, &output_path).unwrap();

    let content = fs::read(&output_path).unwrap();
    let expected_hash = "65e39989ca91c49484998aa3f0429f6943c029609bfd2f3c18c77bf9ded72c59";
    let expected_preamble = replace_bytes(preamble_text, PLACEHOLDER, expected_hash.as_bytes());

    assert!(content.starts_with(&expected_preamble));
    assert!(content.ends_with(zip_content));

    let _ = fs::remove_dir_all(&temp_dir);
}

#[test]
fn test_create_exe_zip_creates_parent_dir() {
    let temp_dir = env::temp_dir().join(format!("create_exe_zip_parent_{}", std::process::id()));
    fs::create_dir_all(&temp_dir).unwrap();

    let preamble_path = temp_dir.join("preamble.sh");
    let zip_path = temp_dir.join("data.zip");
    let output_path = temp_dir.join("nested").join("sub").join("output.exe");

    fs::write(&zip_path, b"content").unwrap();
    fs::write(&preamble_path, b"preamble").unwrap();

    create_exe_zip(&preamble_path, &zip_path, &output_path).unwrap();
    assert!(output_path.exists());

    let _ = fs::remove_dir_all(&temp_dir);
}

#[test]
fn test_create_exe_zip_missing_files() {
    let temp_dir = env::temp_dir().join(format!("create_exe_zip_err_{}", std::process::id()));
    fs::create_dir_all(&temp_dir).unwrap();

    let missing_preamble = temp_dir.join("nonexistent_preamble.sh");
    let zip_path = temp_dir.join("data.zip");
    let output_path = temp_dir.join("output.exe");
    fs::write(&zip_path, b"dummy").unwrap();

    assert!(create_exe_zip(&missing_preamble, &zip_path, &output_path).is_err());

    let preamble_path = temp_dir.join("preamble.sh");
    fs::write(&preamble_path, b"preamble").unwrap();
    let missing_zip = temp_dir.join("nonexistent_data.zip");

    assert!(create_exe_zip(&preamble_path, &missing_zip, &output_path).is_err());

    let _ = fs::remove_dir_all(&temp_dir);
}

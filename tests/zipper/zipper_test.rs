use std::collections::HashMap;
use std::env;
use std::fs::{self, File};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

use zip::{CompressionMethod, DateTime, ZipArchive};
use zipper_lib::{create_zip, parse_args, relative_path, Cli, ZipOptions};

static TEST_COUNTER: AtomicUsize = AtomicUsize::new(0);

/// Reads all entries from a ZIP file on disk using `zip::ZipArchive` (which verifies CRC-32).
fn read_zip_entries(zip_path: &Path) -> Vec<ParsedZipEntry> {
    let file = File::open(zip_path).expect("open output zip");
    let mut archive = ZipArchive::new(file).expect("parse output zip");
    let mut entries = Vec::with_capacity(archive.len());

    for i in 0..archive.len() {
        let mut entry = archive.by_index(i).expect("read zip entry");
        let mut data = Vec::with_capacity(entry.size() as usize);
        entry.read_to_end(&mut data).expect("read zip entry data");
        assert_eq!(
            data.len() as u64,
            entry.size(),
            "uncompressed size mismatch for {}",
            entry.name()
        );

        entries.push(ParsedZipEntry {
            name: entry.name().to_string(),
            compression: entry.compression(),
            last_modified: entry.last_modified(),
            compress_size: entry.compressed_size(),
            file_size: entry.size(),
            unix_mode: entry.unix_mode(),
            is_symlink: entry.is_symlink(),
            data,
        });
    }

    entries
}

fn default_options(manifest_path: &Path, output_zip: &Path) -> ZipOptions {
    ZipOptions {
        manifest_path: manifest_path.to_path_buf(),
        output_zip: output_zip.to_path_buf(),
        compress_level: 0,
        workspace_name: "my_ws".to_string(),
        legacy_external_runfiles: false,
        runfiles_dir: "runfiles".to_string(),
        platform_pathsep: "/".to_string(),
    }
}

#[test]
fn test_create_zip_with_files_and_symlinks() {
    let tmp = TempDir::new("files_and_symlinks");
    let manifest_path = tmp.path().join("manifest.txt");
    let output_zip = tmp.path().join("output.zip");

    let file1_path = tmp.path().join("file1.txt");
    fs::write(&file1_path, b"content1").expect("write file1_path");

    #[cfg(unix)]
    let symlink_path = {
        let p = tmp.path().join("symlink_source");
        std::os::unix::fs::symlink("target.txt", &p).expect("create symlink_source");
        p
    };

    let mut manifest_lines = vec![
        format!("regular|0|file1.txt|{}", file1_path.display()),
        format!("rf-file|0|foo/bar.txt|{}", file1_path.display()),
        format!("rf-root-symlink|0|root_file|{}", file1_path.display()),
        "rf-empty|empty_file".to_string(),
    ];
    #[cfg(unix)]
    manifest_lines.push(format!("rf-symlink|1|link1|{}", symlink_path.display()));

    fs::write(&manifest_path, manifest_lines.join("\n")).expect("write manifest");

    let opts = default_options(&manifest_path, &output_zip);
    create_zip(&opts).expect("create_zip");

    let entries = read_zip_entries(&output_zip);
    let by_name: HashMap<String, ParsedZipEntry> =
        entries.into_iter().map(|e| (e.name.clone(), e)).collect();

    assert_eq!(by_name["file1.txt"].text(), "content1");
    assert!(!by_name["file1.txt"].is_symlink);

    assert_eq!(by_name["runfiles/my_ws/foo/bar.txt"].text(), "content1");
    assert!(!by_name["runfiles/my_ws/foo/bar.txt"].is_symlink);

    assert_eq!(by_name["runfiles/root_file"].text(), "content1");
    assert!(!by_name["runfiles/root_file"].is_symlink);

    assert_eq!(by_name["runfiles/my_ws/empty_file"].text(), "");
    assert!(!by_name["runfiles/my_ws/empty_file"].is_symlink);
    assert_eq!(
        by_name["runfiles/my_ws/empty_file"]
            .unix_mode
            .expect("entry has unix mode")
            & 0o777,
        0o644
    );

    #[cfg(unix)]
    {
        assert!(by_name["runfiles/my_ws/link1"].is_symlink);
        assert_eq!(by_name["runfiles/my_ws/link1"].text(), "target.txt");
    }
}

#[test]
fn test_create_zip_with_direct_symlink() {
    let tmp = TempDir::new("direct_symlink");
    let manifest_path = tmp.path().join("manifest.txt");
    let output_zip = tmp.path().join("output.zip");

    fs::write(&manifest_path, "symlink|path/to/link|target/path\n").expect("write manifest_path");

    let opts = default_options(&manifest_path, &output_zip);
    create_zip(&opts).expect("create_zip");

    let entries = read_zip_entries(&output_zip);
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].name, "runfiles/path/to/link");
    assert!(entries[0].is_symlink);
    assert_eq!(entries[0].text(), "../../target/path");
}

#[cfg(unix)]
#[test]
fn test_create_zip_with_source_symlink_marked_as_regular() {
    let tmp = TempDir::new("source_symlink_regular");
    let manifest_path = tmp.path().join("manifest.txt");
    let output_zip = tmp.path().join("output.zip");

    let target_path = tmp.path().join("python3.14");
    fs::write(&target_path, b"python").expect("write target_path");
    let symlink_path = tmp.path().join("python");
    std::os::unix::fs::symlink("python3.14", &symlink_path).expect("create symlink symlink_path");

    fs::write(
        &manifest_path,
        format!("rf-file|0|bin/python|{}\n", symlink_path.display()),
    )
    .expect("write manifest_path");

    let opts = default_options(&manifest_path, &output_zip);
    create_zip(&opts).expect("create_zip");

    let entries = read_zip_entries(&output_zip);
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].name, "runfiles/my_ws/bin/python");
    assert!(entries[0].is_symlink);
    assert_eq!(entries[0].text(), "python3.14");
}

#[cfg(unix)]
#[test]
fn test_create_zip_with_sandboxed_source_symlink() {
    let tmp = TempDir::new("sandboxed_source_symlink");
    let manifest_path = tmp.path().join("manifest.txt");
    let output_zip = tmp.path().join("output.zip");

    let source_dir = tmp.path().join("source");
    fs::create_dir_all(&source_dir).expect("create source_dir");
    let target_path = source_dir.join("python3.14");
    fs::write(&target_path, b"python").expect("write target_path");
    let source_symlink = source_dir.join("python");
    std::os::unix::fs::symlink("python3.14", &source_symlink)
        .expect("create symlink source_symlink");

    let sandbox_dir = tmp.path().join("sandbox");
    fs::create_dir_all(&sandbox_dir).expect("create sandbox_dir");
    let sandbox_symlink = sandbox_dir.join("python");
    std::os::unix::fs::symlink(&source_symlink, &sandbox_symlink)
        .expect("create symlink sandbox_symlink");
    let sandbox_regular = sandbox_dir.join("python3.14");
    std::os::unix::fs::symlink(&target_path, &sandbox_regular)
        .expect("create symlink sandbox_regular");

    fs::write(
        &manifest_path,
        format!(
            "rf-file|0|bin/python|{}\nrf-file|0|bin/python3.14|{}\n",
            sandbox_symlink.display(),
            sandbox_regular.display()
        ),
    )
    .expect("write manifest_path");

    let opts = default_options(&manifest_path, &output_zip);
    create_zip(&opts).expect("create_zip");

    let entries = read_zip_entries(&output_zip);
    let by_name: HashMap<String, ParsedZipEntry> =
        entries.into_iter().map(|e| (e.name.clone(), e)).collect();

    assert!(by_name["runfiles/my_ws/bin/python"].is_symlink);
    assert_eq!(by_name["runfiles/my_ws/bin/python"].text(), "python3.14");

    assert!(!by_name["runfiles/my_ws/bin/python3.14"].is_symlink);
    assert_eq!(by_name["runfiles/my_ws/bin/python3.14"].text(), "python");
}

#[cfg(unix)]
#[test]
fn test_create_zip_with_sandboxed_absolute_source_symlink() {
    let tmp = TempDir::new("sandboxed_abs_symlink");
    let manifest_path = tmp.path().join("manifest.txt");
    let output_zip = tmp.path().join("output.zip");

    let library_dir = tmp.path().join("external");
    fs::create_dir_all(&library_dir).expect("create library_dir");
    let library = library_dir.join("libfoo.so");
    fs::write(&library, b"library").expect("write library");

    let solib_dir = tmp.path().join("solib");
    fs::create_dir_all(&solib_dir).expect("create solib_dir");
    let solib_link = solib_dir.join("libfoo.so");
    std::os::unix::fs::symlink(&library, &solib_link).expect("create symlink solib_link");

    let sandbox_dir = tmp.path().join("sandbox");
    fs::create_dir_all(&sandbox_dir).expect("create sandbox_dir");
    let sandbox_link = sandbox_dir.join("libfoo.so");
    std::os::unix::fs::symlink(&solib_link, &sandbox_link).expect("create symlink sandbox_link");

    fs::write(
        &manifest_path,
        format!("rf-file|0|_solib/libfoo.so|{}\n", sandbox_link.display()),
    )
    .expect("write manifest_path");

    let opts = default_options(&manifest_path, &output_zip);
    create_zip(&opts).expect("create_zip");

    let entries = read_zip_entries(&output_zip);
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].name, "runfiles/my_ws/_solib/libfoo.so");
    assert!(!entries[0].is_symlink);
    assert_eq!(entries[0].text(), "library");
}

#[cfg(unix)]
#[test]
fn test_is_symlink_minus_one_inference() {
    let tmp = TempDir::new("is_symlink_minus_one");
    let manifest_path = tmp.path().join("manifest.txt");
    let output_zip = tmp.path().join("output.zip");

    let broken_link = tmp.path().join("dangling_link");
    std::os::unix::fs::symlink("nonexistent_target", &broken_link)
        .expect("create symlink broken_link");

    let existing_file = tmp.path().join("real.txt");
    fs::write(&existing_file, b"real content").expect("write existing_file");

    fs::write(
        &manifest_path,
        format!(
            "rf-file|-1|dangling|{}\nrf-file|-1|real|{}\n",
            broken_link.display(),
            existing_file.display()
        ),
    )
    .expect("write manifest_path");

    let opts = default_options(&manifest_path, &output_zip);
    create_zip(&opts).expect("create_zip");

    let entries = read_zip_entries(&output_zip);
    let by_name: HashMap<String, ParsedZipEntry> =
        entries.into_iter().map(|e| (e.name.clone(), e)).collect();

    assert!(by_name["runfiles/my_ws/dangling"].is_symlink);
    assert_eq!(
        by_name["runfiles/my_ws/dangling"].text(),
        "nonexistent_target"
    );
    assert!(!by_name["runfiles/my_ws/real"].is_symlink);
    assert_eq!(by_name["runfiles/my_ws/real"].text(), "real content");
}

#[test]
fn test_pathsep_normalization() {
    let tmp = TempDir::new("pathsep_norm");
    let manifest_path = tmp.path().join("manifest.txt");
    let output_zip = tmp.path().join("output.zip");

    let file1_path = tmp.path().join("file1.txt");
    fs::write(&file1_path, b"content1").expect("write file1_path");

    fs::write(
        &manifest_path,
        format!(
            "regular|0|dir\\file.txt|{}\nsymlink|link/path|target/path\n",
            file1_path.display()
        ),
    )
    .expect("write manifest_path");

    let mut opts = default_options(&manifest_path, &output_zip);
    opts.platform_pathsep = "\\".to_string();
    create_zip(&opts).expect("create_zip");

    let entries = read_zip_entries(&output_zip);
    let by_name: HashMap<String, ParsedZipEntry> =
        entries.into_iter().map(|e| (e.name.clone(), e)).collect();

    assert!(by_name.contains_key("dir/file.txt"));
    assert!(by_name["runfiles/link/path"].is_symlink);
    assert_eq!(by_name["runfiles/link/path"].text(), "..\\target\\path");
}

#[test]
fn test_symlink_precedence() {
    let tmp = TempDir::new("symlink_precedence");
    let manifest_path = tmp.path().join("manifest.txt");
    let output_zip = tmp.path().join("output.zip");

    let file1_path = tmp.path().join("file1.txt");
    fs::write(&file1_path, b"content1").expect("write file1_path");

    fs::write(
        &manifest_path,
        format!(
            "rf-file|0|path/to/file|{}\nsymlink|my_ws/path/to/file|symlink/target\n",
            file1_path.display()
        ),
    )
    .expect("write manifest_path");

    let opts = default_options(&manifest_path, &output_zip);
    create_zip(&opts).expect("create_zip");

    let entries = read_zip_entries(&output_zip);
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].name, "runfiles/my_ws/path/to/file");
    assert!(entries[0].is_symlink);
    assert_eq!(entries[0].text(), "../../../symlink/target");
}

#[test]
fn test_timestamps_and_permissions_are_deterministic() {
    let tmp = TempDir::new("deterministic_meta");
    let manifest_path = tmp.path().join("manifest.txt");
    let output_zip = tmp.path().join("output.zip");

    let file1_path = tmp.path().join("file1.sh");
    fs::write(&file1_path, b"#!/bin/sh\necho hi\n").expect("write file1_path");
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = fs::metadata(&file1_path)
            .expect("stat file1_path")
            .permissions();
        perms.set_mode(0o755);
        fs::set_permissions(&file1_path, perms).expect("chmod file1_path");
    }

    fs::write(
        &manifest_path,
        format!("regular|0|file1.sh|{}\n", file1_path.display()),
    )
    .expect("write manifest_path");

    let opts = default_options(&manifest_path, &output_zip);
    create_zip(&opts).expect("create_zip");

    let entries = read_zip_entries(&output_zip);
    assert_eq!(entries.len(), 1);
    assert_eq!(
        entries[0].last_modified,
        Some(DateTime::from_date_and_time(1980, 1, 1, 0, 0, 0).expect("valid timestamp"))
    );
    assert!(entries[0].unix_mode.is_some());
    #[cfg(unix)]
    assert_eq!(
        entries[0].unix_mode.expect("entry has unix mode") & 0o777,
        0o755
    );
}

#[test]
fn test_runfiles_mapping_with_cross_repo_paths() {
    let tmp = TempDir::new("cross_repo");
    let manifest_path = tmp.path().join("manifest.txt");
    let output_zip = tmp.path().join("output.zip");

    let file1_path = tmp.path().join("file1.txt");
    fs::write(&file1_path, b"content1").expect("write file1_path");

    fs::write(
        &manifest_path,
        format!(
            "rf-file|0|../other_repo/foo.txt|{}\nrf-empty|../other_repo/empty_file\n",
            file1_path.display()
        ),
    )
    .expect("write manifest_path");

    let opts = default_options(&manifest_path, &output_zip);
    create_zip(&opts).expect("create_zip");

    let entries = read_zip_entries(&output_zip);
    let by_name: HashMap<String, ParsedZipEntry> =
        entries.into_iter().map(|e| (e.name.clone(), e)).collect();

    assert_eq!(by_name.len(), 2);
    assert_eq!(by_name["runfiles/other_repo/foo.txt"].text(), "content1");
    assert_eq!(by_name["runfiles/other_repo/empty_file"].text(), "");
}

#[test]
fn test_runfiles_mapping_with_legacy_external_paths() {
    let tmp = TempDir::new("legacy_external");
    let manifest_path = tmp.path().join("manifest.txt");
    let output_zip = tmp.path().join("output.zip");

    let file1_path = tmp.path().join("file1.txt");
    fs::write(&file1_path, b"content1").expect("write file1_path");

    fs::write(
        &manifest_path,
        format!(
            "rf-file|0|external/other_repo/foo.txt|{}\nrf-empty|external/other_repo/empty_file\n",
            file1_path.display()
        ),
    )
    .expect("write manifest_path");

    let mut opts = default_options(&manifest_path, &output_zip);
    opts.legacy_external_runfiles = true;
    create_zip(&opts).expect("create_zip");

    let entries = read_zip_entries(&output_zip);
    let by_name: HashMap<String, ParsedZipEntry> =
        entries.into_iter().map(|e| (e.name.clone(), e)).collect();

    assert_eq!(by_name.len(), 2);
    assert_eq!(by_name["runfiles/other_repo/foo.txt"].text(), "content1");
    assert_eq!(by_name["runfiles/other_repo/empty_file"].text(), "");
}

#[test]
fn test_output_deterministic_ordering() {
    let tmp = TempDir::new("deterministic_order");
    let manifest_path = tmp.path().join("manifest.txt");
    let output_zip = tmp.path().join("output.zip");

    let file1 = tmp.path().join("file1");
    fs::write(&file1, b"1").expect("write file1");
    let file2 = tmp.path().join("file2");
    fs::write(&file2, b"2").expect("write file2");
    let file3 = tmp.path().join("file3");
    fs::write(&file3, b"3").expect("write file3");

    fs::write(
        &manifest_path,
        [
            format!("regular|0|z/regular|{}", file1.display()),
            format!("rf-file|0|b_rf_file|{}", file2.display()),
            format!("rf-root-symlink|0|a_root_link|{}", file3.display()),
            format!("regular|0|a/regular|{}", file3.display()),
            "rf-empty|d_rf_empty".to_string(),
            format!("rf-symlink|0|c_rf_link|{}", file3.display()),
        ]
        .join("\n"),
    )
    .expect("write manifest");

    let opts = default_options(&manifest_path, &output_zip);
    create_zip(&opts).expect("create_zip");

    let names: Vec<String> = read_zip_entries(&output_zip)
        .into_iter()
        .map(|e| e.name)
        .collect();

    assert_eq!(
        names,
        vec![
            "a/regular",
            "runfiles/a_root_link",
            "runfiles/my_ws/b_rf_file",
            "runfiles/my_ws/c_rf_link",
            "runfiles/my_ws/d_rf_empty",
            "z/regular",
        ]
    );
}

#[test]
fn test_deflated_compression() {
    let tmp = TempDir::new("deflated");
    let manifest_path = tmp.path().join("manifest.txt");
    let output_zip = tmp.path().join("output.zip");

    let file1 = tmp.path().join("repeated.txt");
    let content = "hello world! ".repeat(500);
    fs::write(&file1, content.as_bytes()).expect("write file1");

    fs::write(
        &manifest_path,
        format!(
            "regular|0|repeated.txt|{}\nrf-empty|empty\nsymlink|a/link|b/target\n",
            file1.display()
        ),
    )
    .expect("write manifest_path");

    let mut opts = default_options(&manifest_path, &output_zip);
    opts.compress_level = 6;
    create_zip(&opts).expect("create_zip");

    let entries = read_zip_entries(&output_zip);
    let by_name: HashMap<String, ParsedZipEntry> =
        entries.into_iter().map(|e| (e.name.clone(), e)).collect();

    let rep = &by_name["repeated.txt"];
    assert_eq!(rep.compression, CompressionMethod::Deflated);
    assert!(rep.compress_size < rep.file_size);
    assert_eq!(rep.text(), content);

    let emp = &by_name["runfiles/my_ws/empty"];
    assert_eq!(emp.compression, CompressionMethod::Deflated);
    assert_eq!(emp.text(), "");

    let sym = &by_name["runfiles/a/link"];
    assert_eq!(sym.compression, CompressionMethod::Stored);
    assert!(sym.is_symlink);
}

#[test]
fn test_relative_path_calculations() {
    assert_eq!(
        relative_path("runfiles/target/path", "runfiles/path/to"),
        "../../target/path"
    );
    assert_eq!(
        relative_path("runfiles/my_ws/same_dir_target", "runfiles/my_ws"),
        "same_dir_target"
    );
    assert_eq!(relative_path("runfiles/a", "runfiles/a"), ".");
}

fn expect_run(cli: Cli) -> ZipOptions {
    match cli {
        Cli::Run(opts) => opts,
        Cli::Help => panic!("expected Cli::Run, got Cli::Help"),
    }
}

#[test]
fn test_parse_args_cli() {
    let opts = expect_run(
        parse_args([
            "manifest.txt",
            "out.zip",
            "--compression=4",
            "--workspace-name=_main",
            "--legacy-external-runfiles=1",
            "--runfiles-dir=custom_rf",
            "--target-platform-pathsep=\\",
        ])
        .expect("all flags parse"),
    );

    assert_eq!(opts.manifest_path, PathBuf::from("manifest.txt"));
    assert_eq!(opts.output_zip, PathBuf::from("out.zip"));
    assert_eq!(opts.compress_level, 4);
    assert_eq!(opts.workspace_name, "_main");
    assert!(opts.legacy_external_runfiles);
    assert_eq!(opts.runfiles_dir, "custom_rf");
    assert_eq!(opts.platform_pathsep, "\\");

    let opts2 = expect_run(
        parse_args([
            "--compression",
            "0",
            "--legacy-external-runfiles",
            "0",
            "m.txt",
            "o.zip",
        ])
        .expect("space-separated flags parse"),
    );
    assert_eq!(opts2.compress_level, 0);
    assert!(!opts2.legacy_external_runfiles);

    assert_eq!(parse_args(["--help"]).expect("--help parses"), Cli::Help);
    assert_eq!(parse_args(["a", "b", "-h"]).expect("-h parses"), Cli::Help);

    let err = parse_args(["only_one_arg"])
        .expect_err("one positional must fail")
        .to_string();
    assert!(err.contains("expected 2 positional"), "{err}");
    let err = parse_args(["a", "b", "--legacy-external-runfiles=2"])
        .expect_err("bad bool flag must fail")
        .to_string();
    assert!(err.contains("expected 0 or 1"), "{err}");
    let err = parse_args(["a", "b", "--compression=10"])
        .expect_err("compression 10 must fail")
        .to_string();
    assert!(err.contains("expected 0-9"), "{err}");
    let err = parse_args(["a", "b", "--unknown-flag"])
        .expect_err("unknown flag must fail")
        .to_string();
    assert!(err.contains("unknown-flag"), "{err}");
}

#[cfg(unix)]
#[test]
fn test_symlink_extraction() {
    let tmp = TempDir::new("symlink_extraction");
    let manifest_path = tmp.path().join("manifest.txt");
    let output_zip = tmp.path().join("output.zip");

    let target_file = tmp.path().join("target_file.txt");
    fs::write(&target_file, b"target content").expect("write target_file");

    fs::write(
        &manifest_path,
        [
            format!("rf-file|0|target/path|{}", target_file.display()),
            "symlink|my_ws/path/to/link|my_ws/target/path".to_string(),
            format!("rf-file|0|same_dir_target|{}", target_file.display()),
            "symlink|my_ws/same_dir_link|my_ws/same_dir_target".to_string(),
        ]
        .join("\n"),
    )
    .expect("write manifest");

    let opts = default_options(&manifest_path, &output_zip);
    create_zip(&opts).expect("create_zip");

    let extract_dir = tmp.path().join("extract");
    fs::create_dir_all(&extract_dir).expect("create extract_dir");

    for entry in read_zip_entries(&output_zip) {
        let extract_path = extract_dir.join(&entry.name);
        if let Some(parent) = extract_path.parent() {
            fs::create_dir_all(parent).expect("create parent dir");
        }
        if entry.is_symlink {
            std::os::unix::fs::symlink(entry.text(), &extract_path)
                .expect("create symlink extract_path");
        } else {
            fs::write(&extract_path, &entry.data).expect("write extract_path");
        }
    }

    let link_path = extract_dir.join("runfiles/my_ws/path/to/link");
    assert!(fs::symlink_metadata(&link_path)
        .expect("lstat link_path")
        .file_type()
        .is_symlink());
    assert_eq!(
        fs::read_link(&link_path).expect("readlink link_path"),
        PathBuf::from("../../target/path")
    );
    assert_eq!(
        fs::read_to_string(&link_path).expect("read link_path"),
        "target content"
    );

    let link2_path = extract_dir.join("runfiles/my_ws/same_dir_link");
    assert!(fs::symlink_metadata(&link2_path)
        .expect("lstat link2_path")
        .file_type()
        .is_symlink());
    assert_eq!(
        fs::read_link(&link2_path).expect("readlink link2_path"),
        PathBuf::from("same_dir_target")
    );
    assert_eq!(
        fs::read_to_string(&link2_path).expect("read link2_path"),
        "target content"
    );
}

#[test]
fn test_invalid_manifest_line_returns_error() {
    let tmp = TempDir::new("invalid_manifest");
    let manifest_path = tmp.path().join("manifest.txt");
    let output_zip = tmp.path().join("output.zip");

    fs::write(&manifest_path, "unknown_type|foo|bar\n").expect("write manifest_path");

    let opts = default_options(&manifest_path, &output_zip);
    let err = format!(
        "{:#}",
        create_zip(&opts).expect_err("malformed manifest must fail")
    );
    assert!(err.contains("manifest line 1: unknown entry type"), "{err}");
}

#[test]
fn test_invalid_is_symlink_value_returns_error() {
    let tmp = TempDir::new("invalid_is_symlink");
    let manifest_path = tmp.path().join("manifest.txt");
    let output_zip = tmp.path().join("output.zip");

    let file1_path = tmp.path().join("file1.txt");
    fs::write(&file1_path, b"content1").expect("write file1_path");
    fs::write(
        &manifest_path,
        format!("rf-file|5|foo|{}\n", file1_path.display()),
    )
    .expect("write manifest_path");

    let opts = default_options(&manifest_path, &output_zip);
    let err = format!(
        "{:#}",
        create_zip(&opts).expect_err("bad is_symlink must fail")
    );
    assert!(
        err.contains("manifest line 1: invalid is_symlink value"),
        "{err}"
    );
}

#[test]
fn test_compress_level_out_of_range_returns_error() {
    let tmp = TempDir::new("compress_level_range");
    let manifest_path = tmp.path().join("manifest.txt");
    let output_zip = tmp.path().join("output.zip");
    fs::write(&manifest_path, "rf-empty|empty\n").expect("write manifest_path");

    let mut opts = default_options(&manifest_path, &output_zip);
    opts.compress_level = 10;
    let err = format!(
        "{:#}",
        create_zip(&opts).expect_err("compress_level 10 must fail")
    );
    assert!(err.contains("expected 0-9"), "{err}");
    assert!(!output_zip.exists());
}

struct TempDir {
    path: PathBuf,
}

impl TempDir {
    fn new(prefix: &str) -> Self {
        let id = TEST_COUNTER.fetch_add(1, Ordering::SeqCst);
        let path = env::temp_dir().join(format!(
            "zipper_test_{}_{}_{}",
            prefix,
            std::process::id(),
            id
        ));
        let _ = fs::remove_dir_all(&path);
        fs::create_dir_all(&path).expect("create temp dir");
        Self { path }
    }

    fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

#[derive(Debug)]
struct ParsedZipEntry {
    /// Entry path inside the zip archive, relative to the zip root.
    name: String,
    compression: CompressionMethod,
    last_modified: Option<DateTime>,
    compress_size: u64,
    file_size: u64,
    unix_mode: Option<u32>,
    is_symlink: bool,
    data: Vec<u8>,
}

impl ParsedZipEntry {
    fn text(&self) -> &str {
        std::str::from_utf8(&self.data).expect("entry data is UTF-8")
    }
}

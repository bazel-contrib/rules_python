use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::{Command, ExitCode};

use shrubbery_lib::{SUBCOMMANDS, run_cli};

fn temp_test_dir(prefix: &str) -> PathBuf {
    let base = env::var_os("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(env::temp_dir);
    let dir = base.join(format!("shrubbery_{}_{}", prefix, std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).expect("temp dir should be creatable");
    dir
}

#[test]
fn test_subcommands_registry_sorted_and_complete() {
    assert_eq!(SUBCOMMANDS.len(), 6);
    let mut sorted = SUBCOMMANDS.to_vec();
    sorted.sort_unstable();
    assert_eq!(SUBCOMMANDS, sorted.as_slice());
}

#[test]
fn test_help_flags_exit_zero() {
    assert_eq!(run_cli(["shrubbery", "--help"]), ExitCode::SUCCESS);
    assert_eq!(run_cli(["shrubbery", "-h"]), ExitCode::SUCCESS);
    assert_eq!(run_cli(["shrubbery", "help"]), ExitCode::SUCCESS);
}

#[test]
fn test_missing_or_unknown_subcommand_exits_one() {
    assert_eq!(run_cli(["shrubbery"]), ExitCode::FAILURE);
    assert_eq!(run_cli(["shrubbery", "does_not_exist"]), ExitCode::FAILURE);
}

#[test]
fn test_subcommand_forwarding() {
    let dir = temp_test_dir("dispatch");
    let preamble = dir.join("preamble.sh");
    let zip_in = dir.join("in.zip");
    let out_pyz = dir.join("out.pyz");

    fs::write(&preamble, b"#!/bin/sh\n").expect("preamble should be writable");
    fs::write(
        &zip_in,
        b"PK\x05\x06\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
    )
    .expect("zip_in should be writable");

    assert_eq!(
        run_cli([
            "shrubbery",
            "exe_zip_maker",
            preamble.to_str().expect("preamble path should be UTF-8"),
            zip_in.to_str().expect("zip_in path should be UTF-8"),
            out_pyz.to_str().expect("out_pyz path should be UTF-8"),
        ]),
        ExitCode::SUCCESS
    );
    assert!(out_pyz.exists());

    let tpl = dir.join("tpl.py");
    let manifest = dir.join("manifest.txt");
    let out_main = dir.join("__main__.py");
    fs::write(&tpl, "HASH=%APP_HASH%\n").expect("tpl should be writable");
    fs::write(&manifest, "rf-empty|__init__.py\n").expect("manifest should be writable");

    assert_eq!(
        run_cli([
            "shrubbery",
            "zip_main_maker",
            "--template",
            tpl.to_str().expect("tpl path should be UTF-8"),
            "--output",
            out_main.to_str().expect("out_main path should be UTF-8"),
            "--hash_files_manifest",
            manifest.to_str().expect("manifest path should be UTF-8"),
        ]),
        ExitCode::SUCCESS
    );
    assert!(out_main.exists());

    let metadata = dir.join("metadata.txt");
    let out_whl = dir.join("pkg-1.0.0-py3-none-any.whl");
    fs::write(&metadata, "Metadata-Version: 2.1\nName: pkg\n")
        .expect("metadata should be writable");

    assert_eq!(
        run_cli([
            "shrubbery",
            "wheelmaker",
            "--name",
            "pkg",
            "--version",
            "1.0.0",
            "--out",
            out_whl.to_str().expect("out_whl path should be UTF-8"),
            "--metadata_file",
            metadata.to_str().expect("metadata path should be UTF-8"),
        ]),
        ExitCode::SUCCESS
    );
    assert!(out_whl.exists());
}

#[test]
fn test_cli_binary_subprocess() {
    let resolved = PathBuf::from(
        env::var_os("SHRUBBERY_BIN").expect("SHRUBBERY_BIN should be set by the test runner"),
    );

    let help_out = Command::new(&resolved)
        .arg("--help")
        .output()
        .expect("shrubbery --help should run");
    assert_eq!(help_out.status.code(), Some(0));
    let stdout = String::from_utf8_lossy(&help_out.stdout);
    for sub in SUBCOMMANDS {
        assert!(stdout.contains(sub), "missing {} in help: {}", sub, stdout);
        let sub_help = Command::new(&resolved)
            .args([*sub, "--help"])
            .output()
            .expect("registered subcommand should run");
        let sub_stderr = String::from_utf8_lossy(&sub_help.stderr);
        assert!(
            !sub_stderr.contains("unknown subcommand"),
            "registered subcommand {sub} was rejected by run_cli: {sub_stderr}"
        );
    }

    let bad_out = Command::new(&resolved)
        .arg("not_a_subcommand")
        .output()
        .expect("shrubbery should run with a bad subcommand");
    assert_eq!(bad_out.status.code(), Some(1));
    assert!(
        String::from_utf8_lossy(&bad_out.stderr).contains("unknown subcommand"),
        "unexpected stderr: {}",
        String::from_utf8_lossy(&bad_out.stderr)
    );

    let abs_resolved =
        std::path::absolute(&resolved).expect("SHRUBBERY_BIN should resolve to an absolute path");
    let dir = temp_test_dir("subprocess_cwd");
    fs::write(
        dir.join("metadata.txt"),
        "Metadata-Version: 2.1\nName: pkg\n",
    )
    .expect("metadata should be writable");
    let whl_out = Command::new(&abs_resolved)
        .current_dir(&dir)
        .args([
            "wheelmaker",
            "--name=pkg",
            "--version=1.0.0",
            "--metadata_file=metadata.txt",
            "--name_file=wheelname.txt",
        ])
        .output()
        .expect("shrubbery wheelmaker should run in subprocess cwd");
    assert_eq!(
        whl_out.status.code(),
        Some(0),
        "stderr: {}",
        String::from_utf8_lossy(&whl_out.stderr)
    );
    assert!(dir.join("pkg-1.0.0-py3-none-any.whl").exists());
    assert_eq!(
        fs::read_to_string(dir.join("wheelname.txt")).expect("wheelname.txt should exist"),
        "pkg-1.0.0-py3-none-any.whl"
    );
}

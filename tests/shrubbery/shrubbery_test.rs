use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

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
    assert_eq!(SUBCOMMANDS.len(), 2);
    let mut sorted = SUBCOMMANDS.to_vec();
    sorted.sort_unstable();
    assert_eq!(SUBCOMMANDS, sorted.as_slice());
}

#[test]
fn test_help_flags_exit_zero() {
    assert_eq!(run_cli(["shrubbery", "--help"]), 0);
    assert_eq!(run_cli(["shrubbery", "-h"]), 0);
    assert_eq!(run_cli(["shrubbery", "help"]), 0);
}

#[test]
fn test_missing_or_unknown_subcommand_exits_one() {
    assert_eq!(run_cli(["shrubbery"]), 1);
    assert_eq!(run_cli(["shrubbery", "does_not_exist"]), 1);
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
        0
    );
    assert!(out_pyz.exists());
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
}

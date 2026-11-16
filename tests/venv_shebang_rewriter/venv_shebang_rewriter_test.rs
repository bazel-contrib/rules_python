use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::{Command, ExitCode};
use std::sync::atomic::{AtomicUsize, Ordering};

use venv_shebang_rewriter_lib::{
    Cli, Options, TargetOs, UNIX_HEADER, WINDOWS_PYTHON_HEADER, WINDOWS_PYTHONW_HEADER, parse_args,
    rewrite_shebang, rewrite_shebang_bytes, run_cli, split_first_line,
};

static COUNTER: AtomicUsize = AtomicUsize::new(0);

fn parse_run<const N: usize>(args: [&str; N]) -> Options {
    match parse_args(args).expect("arguments should parse successfully") {
        Cli::Run(options) => options,
        Cli::Help => panic!("expected Cli::Run, got Cli::Help"),
    }
}

fn create_temp_dir(prefix: &str) -> PathBuf {
    let id = COUNTER.fetch_add(1, Ordering::SeqCst);
    let dir = env::temp_dir().join(format!(
        "venv_shebang_rewriter_{}_{}_{}",
        prefix,
        std::process::id(),
        id
    ));
    fs::create_dir_all(&dir).unwrap();
    dir
}

#[test]
fn test_split_first_line_standard() {
    let (first, rest) = split_first_line(b"#!python\nimport sys\nprint(1)\n");
    assert_eq!(first, b"#!python\n");
    assert_eq!(rest, b"import sys\nprint(1)\n");
}

#[test]
fn test_split_first_line_no_newline() {
    let (first, rest) = split_first_line(b"#!python");
    assert_eq!(first, b"#!python");
    assert_eq!(rest, b"");
}

#[test]
fn test_split_first_line_empty() {
    let (first, rest) = split_first_line(b"");
    assert_eq!(first, b"");
    assert_eq!(rest, b"");
}

#[test]
fn test_unix_shebang_rewrite_and_permissions() {
    let temp_dir = create_temp_dir("unix");
    let in_path = temp_dir.join("script_in");
    let out_path = temp_dir.join("script_out");

    let body = b"# -*- coding: utf-8 -*-\nimport sys\nfrom pkg import main\nif __name__ == '__main__':\n    sys.exit(main())\n";
    let mut input = b"#!python\n".to_vec();
    input.extend_from_slice(body);
    fs::write(&in_path, &input).unwrap();

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&in_path, fs::Permissions::from_mode(0o644)).unwrap();
    }

    rewrite_shebang(&in_path, &out_path, TargetOs::Unix).unwrap();

    let actual = fs::read(&out_path).unwrap();
    let mut expected = UNIX_HEADER.to_vec();
    expected.extend_from_slice(body);
    assert_eq!(actual, expected);

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = fs::metadata(&out_path).unwrap().permissions().mode();
        assert_eq!(
            mode & 0o111,
            0o111,
            "Expected all executable bits (0o111) to be set, got {mode:o}"
        );
    }

    let _ = fs::remove_dir_all(&temp_dir);
}

#[test]
fn test_windows_python_shebang_rewrite() {
    let temp_dir = create_temp_dir("win_python");
    let in_path = temp_dir.join("script_in");
    let out_path = temp_dir.join("script_out.bat");

    let body = b"import sys\r\nprint('hello from windows')\r\n";
    let mut input = b"#!python\r\n".to_vec();
    input.extend_from_slice(body);
    fs::write(&in_path, &input).unwrap();

    rewrite_shebang(&in_path, &out_path, TargetOs::Windows).unwrap();

    let actual = fs::read(&out_path).unwrap();
    let mut expected = WINDOWS_PYTHON_HEADER.to_vec();
    expected.extend_from_slice(body);
    assert_eq!(actual, expected);
    assert!(actual.starts_with(
        b"@setlocal enabledelayedexpansion & \"%~dp0python.exe\" -x \"%~f0\" %* & exit /b !ERRORLEVEL!\r\n"
    ));

    let _ = fs::remove_dir_all(&temp_dir);
}

#[test]
fn test_windows_pythonw_shebang_rewrite() {
    let temp_dir = create_temp_dir("win_pythonw");
    let in_path = temp_dir.join("script_in");
    let out_path = temp_dir.join("script_out.bat");

    let body = b"import sys\nprint('hello from pythonw')\n";
    let mut input = b"#!pythonw\n".to_vec();
    input.extend_from_slice(body);
    fs::write(&in_path, &input).unwrap();

    rewrite_shebang(&in_path, &out_path, TargetOs::Windows).unwrap();

    let actual = fs::read(&out_path).unwrap();
    let mut expected = WINDOWS_PYTHONW_HEADER.to_vec();
    expected.extend_from_slice(body);
    assert_eq!(actual, expected);
    assert!(actual.starts_with(
        b"@setlocal enabledelayedexpansion & \"%~dp0pythonw.exe\" -x \"%~f0\" %* & exit /b !ERRORLEVEL!\r\n"
    ));

    let _ = fs::remove_dir_all(&temp_dir);
}

#[test]
fn test_windows_pythonw_exe_or_flags_prefix() {
    let input = b"#!pythonw.exe -u\nprint('gui')\n";
    let actual = rewrite_shebang_bytes(input, TargetOs::Windows);
    let mut expected = WINDOWS_PYTHONW_HEADER.to_vec();
    expected.extend_from_slice(b"print('gui')\n");
    assert_eq!(actual, expected);
}

#[test]
fn test_unix_ignores_pythonw_distinction() {
    let input = b"#!pythonw\nprint('gui on unix')\n";
    let actual = rewrite_shebang_bytes(input, TargetOs::Unix);
    let mut expected = UNIX_HEADER.to_vec();
    expected.extend_from_slice(b"print('gui on unix')\n");
    assert_eq!(actual, expected);
}

#[test]
fn test_preserves_binary_and_non_utf8_bytes_verbatim() {
    let temp_dir = create_temp_dir("binary_bytes");
    let in_path = temp_dir.join("binary_in");
    let out_path = temp_dir.join("binary_out");

    // First line contains arbitrary bytes before '\n', body contains invalid UTF-8 and NUL bytes
    // as well as mixed LF and CRLF sequences.
    let first_line = b"#!python \xff\xfe\n";
    let binary_rest = b"\x00\x80\xfe\xff\r\nraw_bytes = b'\\x00'\n\x90\x91";
    let mut input = first_line.to_vec();
    input.extend_from_slice(binary_rest);
    fs::write(&in_path, &input).unwrap();

    rewrite_shebang(&in_path, &out_path, TargetOs::Unix).unwrap();

    let actual = fs::read(&out_path).unwrap();
    let mut expected = UNIX_HEADER.to_vec();
    expected.extend_from_slice(binary_rest);
    assert_eq!(actual, expected);

    let _ = fs::remove_dir_all(&temp_dir);
}

#[test]
fn test_single_line_without_trailing_newline() {
    let temp_dir = create_temp_dir("single_line");
    let in_path = temp_dir.join("single_in");
    let out_path_unix = temp_dir.join("single_out_unix");
    let out_path_win = temp_dir.join("single_out_win.bat");

    fs::write(&in_path, b"#!pythonw").unwrap();

    rewrite_shebang(&in_path, &out_path_unix, TargetOs::Unix).unwrap();
    assert_eq!(fs::read(&out_path_unix).unwrap(), UNIX_HEADER);

    rewrite_shebang(&in_path, &out_path_win, TargetOs::Windows).unwrap();
    assert_eq!(fs::read(&out_path_win).unwrap(), WINDOWS_PYTHONW_HEADER);

    let _ = fs::remove_dir_all(&temp_dir);
}

#[test]
fn test_empty_file() {
    let temp_dir = create_temp_dir("empty");
    let in_path = temp_dir.join("empty_in");
    let out_path_unix = temp_dir.join("empty_out_unix");
    let out_path_win = temp_dir.join("empty_out_win.bat");

    fs::write(&in_path, b"").unwrap();

    rewrite_shebang(&in_path, &out_path_unix, TargetOs::Unix).unwrap();
    assert_eq!(fs::read(&out_path_unix).unwrap(), UNIX_HEADER);

    rewrite_shebang(&in_path, &out_path_win, TargetOs::Windows).unwrap();
    assert_eq!(fs::read(&out_path_win).unwrap(), WINDOWS_PYTHON_HEADER);

    let _ = fs::remove_dir_all(&temp_dir);
}

#[test]
fn test_parse_args_and_missing_args_error() {
    assert!(parse_args::<_, &str>([]).is_err());
    assert!(parse_args(["in.py"]).is_err());
    assert!(parse_args(["in.py", "out.py"]).is_err());
    assert!(parse_args(["in.py", "out.py", "unix", "extra"]).is_err());
    assert!(parse_args(["in.py", "out.py", "macos"]).is_err());
    assert!(parse_args(["--unknown", "in.py", "out.py", "unix"]).is_err());
    assert_eq!(run_cli(["only_one_arg"]), ExitCode::FAILURE);

    assert_eq!(
        parse_run(["in.py", "out.py", "windows"]),
        Options {
            in_path: PathBuf::from("in.py"),
            out_path: PathBuf::from("out.py"),
            target_os: TargetOs::Windows,
        }
    );
    assert_eq!(
        parse_run(["in.py", "out.py", "unix"]).target_os,
        TargetOs::Unix
    );
}

#[test]
fn test_parse_args_help() {
    assert_eq!(
        parse_args(["--help"]).expect("--help should parse successfully"),
        Cli::Help
    );
    assert_eq!(
        parse_args(["-h"]).expect("-h should parse successfully"),
        Cli::Help
    );
    assert_eq!(run_cli(["--help"]), ExitCode::SUCCESS);
}

#[test]
fn test_nonexistent_input_file_returns_error() {
    let temp_dir = create_temp_dir("missing_in");
    let missing_in = temp_dir.join("does_not_exist");
    let out_path = temp_dir.join("out");

    assert!(rewrite_shebang(&missing_in, &out_path, TargetOs::Unix).is_err());
    assert_eq!(
        run_cli([
            missing_in.to_str().unwrap(),
            out_path.to_str().unwrap(),
            "unix"
        ]),
        ExitCode::FAILURE
    );

    let _ = fs::remove_dir_all(&temp_dir);
}

#[test]
fn test_cli_binary_execution_and_error_exit_code() {
    let temp_dir = create_temp_dir("cli_bin");
    let in_path = temp_dir.join("cli_in.py");
    let out_path = temp_dir.join("cli_out");

    fs::write(&in_path, b"#!/usr/bin/env python3\nprint('cli ok')\n").unwrap();
    assert_eq!(
        run_cli([
            in_path.to_str().unwrap(),
            out_path.to_str().unwrap(),
            "unix"
        ]),
        ExitCode::SUCCESS
    );

    let mut expected = UNIX_HEADER.to_vec();
    expected.extend_from_slice(b"print('cli ok')\n");
    assert_eq!(fs::read(&out_path).unwrap(), expected);

    let Some(bin_rel) = env::var_os("SHRUBBERY_BIN") else {
        let _ = fs::remove_dir_all(&temp_dir);
        return;
    };
    let bin_path = PathBuf::from(bin_rel);
    if !bin_path.exists() {
        let _ = fs::remove_dir_all(&temp_dir);
        return;
    }

    let bin_out_path = temp_dir.join("bin_cli_out");
    let status = Command::new(&bin_path)
        .arg("venv_shebang_rewriter")
        .arg(&in_path)
        .arg(&bin_out_path)
        .arg("unix")
        .status()
        .unwrap();
    assert!(status.success());
    assert_eq!(fs::read(&bin_out_path).unwrap(), expected);

    // Fewer than 3 args should exit with non-zero status.
    let bad_output = Command::new(&bin_path)
        .arg("venv_shebang_rewriter")
        .arg(&in_path)
        .output()
        .unwrap();
    assert!(!bad_output.status.success());
    let stderr = String::from_utf8_lossy(&bad_output.stderr);
    assert!(stderr.contains("Usage:"));

    let _ = fs::remove_dir_all(&temp_dir);
}

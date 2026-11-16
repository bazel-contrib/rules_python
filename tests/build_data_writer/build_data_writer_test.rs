use std::collections::HashMap;
use std::env;
use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::atomic::{AtomicUsize, Ordering};

use build_data_writer_lib::{Cli, Options, parse_env_and_args, run_cli, write_build_data};

static TEST_COUNTER: AtomicUsize = AtomicUsize::new(0);

const NO_ARGS: [&str; 0] = [];

fn create_temp_dir(prefix: &str) -> PathBuf {
    let id = TEST_COUNTER.fetch_add(1, Ordering::SeqCst);
    let dir = env::temp_dir().join(format!(
        "build_data_writer_test_{}_{}_{}",
        prefix,
        std::process::id(),
        id
    ));
    fs::create_dir_all(&dir).unwrap();
    dir
}

fn parse_run(env_map: &HashMap<&str, OsString>) -> Options {
    match parse_env_and_args(NO_ARGS, |k| env_map.get(k).cloned())
        .expect("environment should parse")
    {
        Cli::Run(opts) => opts,
        Cli::Help => panic!("expected Cli::Run, got Cli::Help"),
    }
}

fn base_env(output: &Path) -> HashMap<&'static str, OsString> {
    HashMap::from([
        ("OUTPUT", output.as_os_str().to_owned()),
        ("TARGET", OsString::from("//pkg:bin")),
        ("STAMPED", OsString::from("TRUE")),
    ])
}

#[test]
fn test_env_configuration_both_status_files() {
    let temp_dir = create_temp_dir("env_both");
    let output_path = temp_dir.join("build_data.txt");
    let version_file = temp_dir.join("volatile-status.txt");
    let info_file = temp_dir.join("stable-status.txt");

    fs::write(
        &version_file,
        "BUILD_TIMESTAMP 1700000000\nFORMATTED_DATE 2023 Nov 14 22 13 20 Tue\n",
    )
    .unwrap();
    fs::write(&info_file, "BUILD_HOST build-box\nBUILD_USER builder\n").unwrap();

    let env_map: HashMap<&str, OsString> = HashMap::from([
        ("OUTPUT", output_path.as_os_str().to_owned()),
        (
            "TARGET",
            OsString::from("//tests/build_data:build_data_test"),
        ),
        ("STAMPED", OsString::from("TRUE")),
        ("VERSION_FILE", version_file.as_os_str().to_owned()),
        ("INFO_FILE", info_file.as_os_str().to_owned()),
    ]);

    let opts = parse_run(&env_map);
    assert!(opts.stamped);
    write_build_data(&opts).expect("build data should be writable");

    let result = fs::read_to_string(&output_path).unwrap();
    let expected = concat!(
        "TARGET //tests/build_data:build_data_test\n",
        "STAMPED TRUE\n",
        "BUILD_TIMESTAMP 1700000000\n",
        "FORMATTED_DATE 2023 Nov 14 22 13 20 Tue\n",
        "BUILD_HOST build-box\n",
        "BUILD_USER builder\n",
    );
    assert_eq!(result, expected);

    let _ = fs::remove_dir_all(&temp_dir);
}

#[test]
fn test_help_flag() {
    for help in ["--help", "-h"] {
        let cli = parse_env_and_args([help], |_| None).expect("help flag should parse");
        assert_eq!(cli, Cli::Help, "unexpected result for {help}");
    }
    assert_eq!(run_cli(["--help"]), ExitCode::SUCCESS);
}

#[test]
fn test_run_cli_rejects_arguments() {
    assert_eq!(run_cli(["--unknown-flag"]), ExitCode::FAILURE);
    assert_eq!(run_cli(["--output=/tmp/out.txt"]), ExitCode::FAILURE);
    assert_eq!(run_cli(["positional"]), ExitCode::FAILURE);
}

#[test]
fn test_unexpected_arguments_error() {
    let env_map = base_env(&PathBuf::from("/tmp/out.txt"));

    for (args, token) in [
        (["--unknown-flag"], "--unknown-flag"),
        (["--output=/tmp/out.txt"], "--output"),
        (["positional"], "positional"),
    ] {
        let err = parse_env_and_args(args, |k| env_map.get(k).cloned()).unwrap_err();
        assert!(
            err.to_string().contains(token),
            "unexpected error for {args:?}: {err}"
        );
    }
}

#[test]
fn test_stamped_parsing() {
    let output = PathBuf::from("/tmp/out.txt");

    let mut env_map = base_env(&output);
    env_map.insert("STAMPED", OsString::from("TRUE"));
    assert!(parse_run(&env_map).stamped);

    env_map.insert("STAMPED", OsString::from("FALSE"));
    assert!(!parse_run(&env_map).stamped);

    for invalid in ["true", "false", "1", "0", "", "maybe"] {
        env_map.insert("STAMPED", OsString::from(invalid));
        let err = parse_env_and_args(NO_ARGS, |k| env_map.get(k).cloned()).unwrap_err();
        assert!(
            err.to_string().contains("STAMPED"),
            "unexpected error for {invalid:?}: {err}"
        );
    }

    env_map.remove("STAMPED");
    let err = parse_env_and_args(NO_ARGS, |k| env_map.get(k).cloned()).unwrap_err();
    assert!(
        err.to_string().contains("STAMPED"),
        "unexpected error: {err}"
    );
}

#[test]
fn test_missing_required_env_vars() {
    let err = parse_env_and_args(NO_ARGS, |_| None).unwrap_err();
    assert!(
        err.to_string().contains("OUTPUT"),
        "unexpected error: {err}"
    );

    let mut env_map = base_env(&PathBuf::from("/tmp/out.txt"));
    env_map.remove("TARGET");
    let err = parse_env_and_args(NO_ARGS, |k| env_map.get(k).cloned()).unwrap_err();
    assert!(
        err.to_string().contains("TARGET"),
        "unexpected error: {err}"
    );
}

#[test]
fn test_empty_or_unset_version_and_info_files() {
    let temp_dir = create_temp_dir("empty_unset");
    let output_path = temp_dir.join("unstamped.txt");
    let empty_file = temp_dir.join("empty.txt");
    fs::write(&empty_file, "").unwrap();

    // Case 1: Both VERSION_FILE and INFO_FILE unset
    let opts = Options {
        output: output_path.clone(),
        target: "//foo:bar".to_string(),
        stamped: false,
        version_file: None,
        info_file: None,
    };
    write_build_data(&opts).expect("build data should be writable");
    assert_eq!(
        fs::read_to_string(&output_path).unwrap(),
        "TARGET //foo:bar\nSTAMPED FALSE\n"
    );

    // Case 2: VERSION_FILE and INFO_FILE set to empty strings in env
    let mut env_map = base_env(&output_path);
    env_map.insert("TARGET", OsString::from("//foo:baz"));
    env_map.insert("VERSION_FILE", OsString::new());
    env_map.insert("INFO_FILE", OsString::new());

    let parsed = parse_run(&env_map);
    assert_eq!(parsed.version_file, None);
    assert_eq!(parsed.info_file, None);
    write_build_data(&parsed).expect("build data should be writable");
    assert_eq!(
        fs::read_to_string(&output_path).unwrap(),
        "TARGET //foo:baz\nSTAMPED TRUE\n"
    );

    // Case 3: VERSION_FILE points to a 0-byte file
    let opts_empty_file = Options {
        output: output_path.clone(),
        target: "//foo:qux".to_string(),
        stamped: true,
        version_file: Some(empty_file),
        info_file: None,
    };
    write_build_data(&opts_empty_file).expect("build data should be writable");
    assert_eq!(
        fs::read_to_string(&output_path).unwrap(),
        "TARGET //foo:qux\nSTAMPED TRUE\n"
    );

    let _ = fs::remove_dir_all(&temp_dir);
}

#[test]
fn test_status_files_without_trailing_newline() {
    let temp_dir = create_temp_dir("no_newline");
    let output_path = temp_dir.join("out.txt");
    let version_file = temp_dir.join("volatile.txt");
    let info_file = temp_dir.join("stable.txt");

    // Neither file ends with '\n'
    fs::write(&version_file, "BUILD_TIMESTAMP 123").unwrap();
    fs::write(&info_file, "BUILD_USER bob").unwrap();

    let opts = Options {
        output: output_path.clone(),
        target: "//a:b".to_string(),
        stamped: true,
        version_file: Some(version_file),
        info_file: Some(info_file),
    };
    write_build_data(&opts).expect("build data should be writable");

    let content = fs::read_to_string(&output_path).unwrap();
    assert_eq!(
        content,
        "TARGET //a:b\nSTAMPED TRUE\nBUILD_TIMESTAMP 123\nBUILD_USER bob\n"
    );

    let _ = fs::remove_dir_all(&temp_dir);
}

#[test]
fn test_truncates_existing_output() {
    let temp_dir = create_temp_dir("truncate");
    let output_path = temp_dir.join("build_data.txt");

    let opts1 = Options {
        output: output_path.clone(),
        target: "//first:target_with_long_previous_content".to_string(),
        stamped: true,
        version_file: None,
        info_file: None,
    };
    write_build_data(&opts1).expect("build data should be writable");

    let opts2 = Options {
        output: output_path.clone(),
        target: "//second:short".to_string(),
        stamped: false,
        version_file: None,
        info_file: None,
    };
    write_build_data(&opts2).expect("build data should be writable");

    let content = fs::read_to_string(&output_path).unwrap();
    assert_eq!(content, "TARGET //second:short\nSTAMPED FALSE\n");

    let _ = fs::remove_dir_all(&temp_dir);
}

#[test]
fn test_missing_status_file_errors() {
    let temp_dir = create_temp_dir("errors");

    let opts = Options {
        output: temp_dir.join("out.txt"),
        target: "//t:t".to_string(),
        stamped: true,
        version_file: Some(temp_dir.join("does_not_exist.txt")),
        info_file: None,
    };
    let err = write_build_data(&opts).unwrap_err();
    assert!(
        format!("{err:#}").contains("does_not_exist.txt"),
        "unexpected error: {err:#}"
    );

    let _ = fs::remove_dir_all(&temp_dir);
}

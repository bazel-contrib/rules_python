use std::collections::HashSet;
use std::env;
use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::atomic::{AtomicUsize, Ordering};

use wheel_record_rewriter_lib::{
    Cli, Options, TargetOs, parse_args, rewrite_entry_path, rewrite_record, rewrite_record_files,
    rewrite_record_str, run_cli,
};

static TEST_COUNTER: AtomicUsize = AtomicUsize::new(0);

/// Parses `args` and unwraps the `Cli::Run` variant.
fn parse_run<I, T>(args: I) -> Options
where
    I: IntoIterator<Item = T>,
    T: Into<OsString>,
{
    match parse_args(args).expect("arguments should parse successfully") {
        Cli::Run(opts) => opts,
        Cli::Help => panic!("expected Cli::Run, got Cli::Help"),
    }
}

struct TempDir {
    path: PathBuf,
}

impl TempDir {
    fn new(prefix: &str) -> Self {
        let id = TEST_COUNTER.fetch_add(1, Ordering::SeqCst);
        let path = env::temp_dir().join(format!(
            "wheel_record_rewriter_test_{prefix}_{}_{id}",
            std::process::id(),
        ));
        let _ = fs::remove_dir_all(&path);
        fs::create_dir_all(&path).unwrap();
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

const SAMPLE_INPUT_RECORD: &str = "\
foo-1.0.data/purelib/pkg/__init__.py,sha256=abc,100
foo-1.0.data/purelib/pkg/module.py,sha256=def,200
foo-1.0.data/platlib/pkg/_ext.so,sha256=ghi,300
foo-1.0.data/data/pkg/data.txt,sha256=111,10
foo-1.0.data/headers/pkg/header.h,sha256=222,20
foo-1.0.data/scripts/foo,sha256=444,40
foo-1.0.data/scripts/my_script.sh,sha256=333,30
foo-1.0.data/scripts/plain_tool,sha256=555,50
foo-1.0.data/scripts/my_py_script.py,sha256=666,60
\"foo-1.0.data/purelib/pkg/my file.py\",sha256=abc,100
\"foo-1.0.data/scripts/my tool\",sha256=def,200
\"foo-1.0.data/headers/my,header.h\",sha256=ghi,300
\"foo-1.0.data/scripts/quote\"\"tool\",sha256=jkl,400
foo-1.0.data/custom_dir/custom.txt,sha256=xyz,123
top_level/__init__.py,sha256=aaa,50
foo-1.0.dist-info/METADATA,sha256=bbb,60
foo-1.0.dist-info/RECORD,,
";

const EXPECTED_UNIX_RECORD: &str = "\
pkg/__init__.py,sha256=abc,100
pkg/module.py,sha256=def,200
pkg/_ext.so,sha256=ghi,300
../../../pkg/data.txt,sha256=111,10
../../../include/pkg/header.h,sha256=222,20
../../../bin/foo,sha256=444,40
../../../bin/my_script.sh,sha256=333,30
../../../bin/plain_tool,sha256=555,50
../../../bin/my_py_script.py,sha256=666,60
pkg/my file.py,sha256=abc,100
../../../bin/my tool,sha256=def,200
\"../../../include/my,header.h\",sha256=ghi,300
\"../../../bin/quote\"\"tool\",sha256=jkl,400
foo-1.0.data/custom_dir/custom.txt,sha256=xyz,123
top_level/__init__.py,sha256=aaa,50
foo-1.0.dist-info/METADATA,sha256=bbb,60
foo-1.0.dist-info/RECORD,,
";

const EXPECTED_WINDOWS_WITH_REWRITTEN_SCRIPTS_RECORD: &str = "\
pkg/__init__.py,sha256=abc,100
pkg/module.py,sha256=def,200
pkg/_ext.so,sha256=ghi,300
../../pkg/data.txt,sha256=111,10
../../Include/pkg/header.h,sha256=222,20
../../Scripts/foo.bat,sha256=444,40
../../Scripts/my_script.sh,sha256=333,30
../../Scripts/plain_tool,sha256=555,50
../../Scripts/my_py_script.py.bat,sha256=666,60
pkg/my file.py,sha256=abc,100
../../Scripts/my tool.bat,sha256=def,200
\"../../Include/my,header.h\",sha256=ghi,300
\"../../Scripts/quote\"\"tool.bat\",sha256=jkl,400
foo-1.0.data/custom_dir/custom.txt,sha256=xyz,123
top_level/__init__.py,sha256=aaa,50
foo-1.0.dist-info/METADATA,sha256=bbb,60
foo-1.0.dist-info/RECORD,,
";

const EXPECTED_WINDOWS_NO_REWRITTEN_SCRIPTS_RECORD: &str = "\
pkg/__init__.py,sha256=abc,100
pkg/module.py,sha256=def,200
pkg/_ext.so,sha256=ghi,300
../../pkg/data.txt,sha256=111,10
../../Include/pkg/header.h,sha256=222,20
../../Scripts/foo,sha256=444,40
../../Scripts/my_script.sh,sha256=333,30
../../Scripts/plain_tool,sha256=555,50
../../Scripts/my_py_script.py,sha256=666,60
pkg/my file.py,sha256=abc,100
../../Scripts/my tool,sha256=def,200
\"../../Include/my,header.h\",sha256=ghi,300
\"../../Scripts/quote\"\"tool\",sha256=jkl,400
foo-1.0.data/custom_dir/custom.txt,sha256=xyz,123
top_level/__init__.py,sha256=aaa,50
foo-1.0.dist-info/METADATA,sha256=bbb,60
foo-1.0.dist-info/RECORD,,
";

#[test]
fn test_unix_rewrite_full_record() {
    let temp = TempDir::new("unix");
    let in_path = temp.path().join("input_RECORD");
    let out_path = temp.path().join("unix_RECORD");
    fs::write(&in_path, SAMPLE_INPUT_RECORD).unwrap();

    let args: Vec<OsString> = vec![
        in_path.as_os_str().to_owned(),
        out_path.as_os_str().to_owned(),
        OsString::from("unix"),
        OsString::from("foo-1.0.data"),
        OsString::from("foo"),
        OsString::from("my tool"),
        OsString::from("my_py_script.py"),
        OsString::from("quote\"tool"),
    ];
    let opts = parse_run(&args);
    assert_eq!(opts.target_os, TargetOs::Unix);
    rewrite_record(&opts).unwrap();

    let actual = fs::read_to_string(&out_path).unwrap();
    assert_eq!(actual, EXPECTED_UNIX_RECORD);
}

#[test]
fn test_windows_rewrite_with_rewritten_scripts() {
    let temp = TempDir::new("win_scripts");
    let in_path = temp.path().join("input_RECORD");
    let out_path = temp.path().join("win_RECORD");
    fs::write(&in_path, SAMPLE_INPUT_RECORD).unwrap();

    let args: Vec<OsString> = vec![
        in_path.as_os_str().to_owned(),
        out_path.as_os_str().to_owned(),
        OsString::from("windows"),
        OsString::from("foo-1.0.data"),
        OsString::from("foo"),
        OsString::from("my tool"),
        OsString::from("my_py_script.py"),
        OsString::from("quote\"tool"),
    ];
    let opts = parse_run(&args);
    assert_eq!(opts.target_os, TargetOs::Windows);
    rewrite_record(&opts).unwrap();

    let actual = fs::read_to_string(&out_path).unwrap();
    assert_eq!(actual, EXPECTED_WINDOWS_WITH_REWRITTEN_SCRIPTS_RECORD);
}

#[test]
fn test_windows_rewrite_without_rewritten_scripts() {
    let temp = TempDir::new("win_no_scripts");
    let in_path = temp.path().join("input_RECORD");
    let out_path = temp.path().join("win_no_rewrite_RECORD");
    fs::write(&in_path, SAMPLE_INPUT_RECORD).unwrap();

    let args: Vec<OsString> = vec![
        in_path.as_os_str().to_owned(),
        out_path.as_os_str().to_owned(),
        OsString::from("windows"),
        OsString::from("foo-1.0.data"),
    ];
    let opts = parse_run(&args);
    rewrite_record(&opts).unwrap();

    let actual = fs::read_to_string(&out_path).unwrap();
    assert_eq!(actual, EXPECTED_WINDOWS_NO_REWRITTEN_SCRIPTS_RECORD);
}

#[test]
fn test_crlf_input_normalized_to_lf_output() {
    let temp = TempDir::new("crlf");
    let in_path = temp.path().join("crlf_RECORD");
    let out_path = temp.path().join("out_RECORD");

    let crlf_input = SAMPLE_INPUT_RECORD.replace('\n', "\r\n");
    fs::write(&in_path, crlf_input).unwrap();

    let rewritten_scripts: HashSet<String> = ["foo", "my tool", "my_py_script.py", "quote\"tool"]
        .into_iter()
        .map(String::from)
        .collect();
    rewrite_record_files(
        &in_path,
        &out_path,
        TargetOs::Windows,
        "foo-1.0.data",
        &rewritten_scripts,
    )
    .unwrap();

    let actual_bytes = fs::read(&out_path).unwrap();
    assert!(
        !actual_bytes.contains(&b'\r'),
        "output RECORD should only contain LF line endings"
    );
    assert_eq!(
        String::from_utf8(actual_bytes).unwrap(),
        EXPECTED_WINDOWS_WITH_REWRITTEN_SCRIPTS_RECORD
    );
}

#[test]
fn test_custom_data_dir_and_csv_quoting() {
    let input = "\
\"bar-2.0.data/platlib/pkg/my,ext.pyd\",sha256=123,456
\"bar-2.0.data/custom_dir/quoted,custom.txt\",sha256=789,101
bar-2.0.data/custom_dir/unquoted_custom.txt,sha256=abc,202
other-1.0.data/purelib/pkg/other.py,sha256=def,303
";
    let expected = "\
\"pkg/my,ext.pyd\",sha256=123,456
\"bar-2.0.data/custom_dir/quoted,custom.txt\",sha256=789,101
bar-2.0.data/custom_dir/unquoted_custom.txt,sha256=abc,202
other-1.0.data/purelib/pkg/other.py,sha256=def,303
";
    let rewritten =
        rewrite_record_str(input, TargetOs::Unix, "bar-2.0.data", &HashSet::new()).unwrap();
    assert_eq!(rewritten, expected);
}

#[test]
fn test_parse_args_errors_on_missing_or_invalid_args() {
    assert!(parse_args([""; 0]).is_err());
    assert!(parse_args(["in"]).is_err());
    assert!(parse_args(["in", "out"]).is_err());
    assert!(parse_args(["in", "out", "unix"]).is_err());
    assert!(parse_args(["--unknown-flag", "in", "out", "unix", "pkg.data"]).is_err());
    assert!(parse_args(["-x", "in", "out", "unix", "pkg.data"]).is_err());

    let err = parse_args(["in", "out", "macos", "pkg.data"]).unwrap_err();
    let msg = format!("{err:#}");
    assert!(msg.contains("unsupported target_os 'macos'"), "err: {msg}");
}

#[test]
fn test_parse_args_help() {
    assert_eq!(parse_args(["--help"]).unwrap(), Cli::Help);
    assert_eq!(parse_args(["-h"]).unwrap(), Cli::Help);
    assert_eq!(
        parse_args(["in", "out", "unix", "pkg.data", "--help"]).unwrap(),
        Cli::Help
    );
    assert_eq!(run_cli(["--help"]), ExitCode::SUCCESS);
}

#[test]
fn test_parse_args_deduplicates_rewritten_scripts_and_supports_double_dash() {
    let args = [
        "--",
        "-in_file",
        "-out_file",
        "windows",
        "pkg-1.0.data",
        "tool_a",
        "tool_b",
        "tool_a",
    ];
    let opts = parse_run(args);
    assert_eq!(opts.in_path, PathBuf::from("-in_file"));
    assert_eq!(opts.out_path, PathBuf::from("-out_file"));
    assert_eq!(opts.target_os, TargetOs::Windows);
    assert_eq!(opts.data_dir_basename, "pkg-1.0.data");
    assert_eq!(opts.rewritten_scripts.len(), 2);
    assert!(opts.rewritten_scripts.contains("tool_a"));
    assert!(opts.rewritten_scripts.contains("tool_b"));
}

#[test]
fn test_missing_input_file_returns_error() {
    let temp = TempDir::new("missing_in");
    let in_path = temp.path().join("does_not_exist");
    let out_path = temp.path().join("out_RECORD");

    let res = rewrite_record_files(
        &in_path,
        &out_path,
        TargetOs::Unix,
        "foo-1.0.data",
        &HashSet::new(),
    );
    assert!(res.is_err());
}

#[test]
fn test_empty_input_blank_lines_and_missing_trailing_newline() {
    let empty_out =
        rewrite_record_str("\n\r\n", TargetOs::Unix, "foo-1.0.data", &HashSet::new()).unwrap();
    assert_eq!(empty_out, "");

    let no_newline_in = "foo-1.0.data/purelib/mod.py,sha256=abc,12";
    let no_newline_out = rewrite_record_str(
        no_newline_in,
        TargetOs::Unix,
        "foo-1.0.data",
        &HashSet::new(),
    )
    .unwrap();
    assert_eq!(no_newline_out, "mod.py,sha256=abc,12\n");
}

#[test]
fn test_data_dir_basename_named_data_and_prefix_boundary() {
    let scripts: HashSet<String> = ["cli"].into_iter().map(String::from).collect();
    let input = "\
data/data/share/doc.txt,sha256=111,10
data/scripts/cli,sha256=222,20
data_extra/purelib/untouched.py,sha256=333,30
\"data_extra/purelib/quoted,untouched.py\",sha256=444,40
";
    let expected = "\
../../share/doc.txt,sha256=111,10
../../Scripts/cli.bat,sha256=222,20
data_extra/purelib/untouched.py,sha256=333,30
\"data_extra/purelib/quoted,untouched.py\",sha256=444,40
";
    let actual = rewrite_record_str(input, TargetOs::Windows, "data", &scripts).unwrap();
    assert_eq!(actual, expected);
}

#[test]
fn test_utf8_filenames_and_rewrite_entry_path() {
    let scripts: HashSet<String> = ["outil_é"].into_iter().map(String::from).collect();
    assert_eq!(
        rewrite_entry_path(
            "foo-1.0.data/scripts/outil_é",
            TargetOs::Windows,
            "foo-1.0.data",
            &scripts
        ),
        "../../Scripts/outil_é.bat"
    );

    let input = "\
foo-1.0.data/purelib/pkg/café.py,sha256=abc,10
\"foo-1.0.data/scripts/outil_é\",sha256=def,20
";
    let expected_win = "\
pkg/café.py,sha256=abc,10
../../Scripts/outil_é.bat,sha256=def,20
";
    let actual_win =
        rewrite_record_str(input, TargetOs::Windows, "foo-1.0.data", &scripts).unwrap();
    assert_eq!(actual_win, expected_win);
}

#[test]
fn test_run_cli_exit_codes() {
    let temp = TempDir::new("run_cli");
    let in_path = temp.path().join("in_RECORD");
    let out_path = temp.path().join("out_RECORD");
    fs::write(&in_path, "foo-1.0.data/scripts/app,sha256=abc,10\n").unwrap();

    let ok_code = run_cli([
        in_path.as_os_str(),
        out_path.as_os_str(),
        OsString::from("windows").as_os_str(),
        OsString::from("foo-1.0.data").as_os_str(),
        OsString::from("app").as_os_str(),
    ]);
    assert_eq!(ok_code, ExitCode::SUCCESS);
    assert_eq!(
        fs::read_to_string(&out_path).unwrap(),
        "../../Scripts/app.bat,sha256=abc,10\n"
    );

    let err_code = run_cli(["missing_args"]);
    assert_eq!(err_code, ExitCode::FAILURE);
}

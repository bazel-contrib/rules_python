use std::env;
use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::atomic::{AtomicUsize, Ordering};

use py_console_script_gen_lib::{
    Options, ParsedArgs, parse_args, parse_console_scripts, run, run_cli,
};

static TEST_COUNTER: AtomicUsize = AtomicUsize::new(0);

/// Builds `Options` for direct `run` invocations.
fn options(
    entry_points: &Path,
    out: &Path,
    console_script: Option<&str>,
    console_script_guess: &str,
    shebang: &str,
) -> Options {
    Options {
        entry_points: entry_points.to_path_buf(),
        out: out.to_path_buf(),
        console_script: console_script.map(str::to_owned),
        console_script_guess: console_script_guess.to_owned(),
        shebang: shebang.to_owned(),
    }
}

/// Parses `args` and unwraps the `ParsedArgs::Options` variant.
fn parse_options<I, T>(args: I) -> Options
where
    I: IntoIterator<Item = T>,
    T: Into<OsString>,
{
    match parse_args(args).expect("arguments should parse") {
        ParsedArgs::Options(opts) => opts,
        ParsedArgs::Help => panic!("expected ParsedArgs::Options, got ParsedArgs::Help"),
    }
}

#[test]
fn test_no_console_scripts_error() {
    let tmp = TempDir::new("no_console_scripts");
    let outfile = tmp.path().join("out.py");
    let entry_points = tmp.path().join("entry_points.txt");
    fs::write(&entry_points, "[non_console_scripts]\nfoo = foo.bar:fizz\n").unwrap();

    let err = run(&options(&entry_points, &outfile, None, "", "")).unwrap_err();
    assert_eq!(
        err.to_string(),
        "The package does not provide any console_scripts in its entry_points.txt"
    );
}

#[test]
fn test_empty_console_scripts_section_error() {
    let tmp = TempDir::new("empty_console_scripts");
    let outfile = tmp.path().join("out.py");
    let entry_points = tmp.path().join("entry_points.txt");
    fs::write(&entry_points, "[console_scripts]\n# only a comment\n").unwrap();

    let err = run(&options(&entry_points, &outfile, None, "foo", "")).unwrap_err();
    assert_eq!(
        err.to_string(),
        "The package does not provide any console_scripts in its entry_points.txt"
    );
}

#[test]
fn test_no_entry_point_selected_error() {
    let tmp = TempDir::new("no_entry_point_selected");
    let outfile = tmp.path().join("out.py");
    let entry_points = tmp.path().join("entry_points.txt");
    fs::write(&entry_points, "[console_scripts]\nfoo = foo.bar:fizz\n").unwrap();

    let err = run(&options(&entry_points, &outfile, None, "bar-baz", "")).unwrap_err();
    assert_eq!(
        err.to_string(),
        "Tried to guess that you wanted 'bar-baz', but could not find it. Please select one of the following console scripts: foo"
    );
}

#[test]
fn test_incorrect_entry_point() {
    let tmp = TempDir::new("incorrect_entry_point");
    let outfile = tmp.path().join("out.py");
    let entry_points = tmp.path().join("entry_points.txt");
    fs::write(
        &entry_points,
        "[console_scripts]\nfoo = foo.bar:fizz\nbar = foo.bar:buzz\n",
    )
    .unwrap();

    let err = run(&options(&entry_points, &outfile, Some("baz"), "", "")).unwrap_err();
    assert_eq!(
        err.to_string(),
        "The console_script 'baz' was not found, only the following are available: bar, foo"
    );
}

#[test]
fn test_a_single_entry_point() {
    let tmp = TempDir::new("single_entry_point");
    let entry_points = tmp.path().join("entry_points.txt");
    fs::write(&entry_points, "[console_scripts]\nfoo = foo.bar:baz\n").unwrap();
    let out = tmp.path().join("foo.py");

    run(&options(&entry_points, &out, None, "foo", "")).expect("script should be generated");

    let got = fs::read_to_string(&out).unwrap();
    let want = "\
import sys

# See @rules_python//crates/py_console_script_gen for explanation
if getattr(sys.flags, \"safe_path\", False):
    # We are running on Python 3.11 and we don't need this workaround
    pass
elif \".runfiles\" not in sys.path[0]:
    sys.path = sys.path[1:]

try:
    from foo.bar import baz
except ImportError:
    entries = \"\\n\".join(sys.path)
    print(\"Printing sys.path entries for easier debugging:\", file=sys.stderr)
    print(f\"sys.path is:\\n{entries}\", file=sys.stderr)
    raise

if __name__ == \"__main__\":
    sys.exit(baz())  # pyrefly: ignore[not-callable]
";
    assert_eq!(got, want);
}

#[test]
fn test_a_second_entry_point_class_method() {
    let tmp = TempDir::new("second_entry_point");
    let entry_points = tmp.path().join("entry_points.txt");
    fs::write(
        &entry_points,
        "[console_scripts]\nfoo = foo.bar:Bar.baz\nbar = foo.baz:Bar.baz\n",
    )
    .unwrap();
    let out = tmp.path().join("out.py");

    run(&options(&entry_points, &out, Some("bar"), "", "")).expect("script should be generated");

    let got = fs::read_to_string(&out).unwrap();
    assert!(got.contains("from foo.baz import Bar\n"));
    assert!(got.contains("sys.exit(Bar.baz())  # pyrefly: ignore[not-callable]\n"));
}

#[test]
fn test_shebang_included() {
    let tmp = TempDir::new("shebang_included");
    let entry_points = tmp.path().join("entry_points.txt");
    fs::write(&entry_points, "[console_scripts]\nfoo = foo.bar:baz\n").unwrap();
    let out = tmp.path().join("foo.py");

    let shebang = "#!/usr/bin/env python3";
    run(&options(&entry_points, &out, None, "foo", shebang)).expect("script should be generated");

    let got = fs::read_to_string(&out).unwrap();
    assert!(got.starts_with("#!/usr/bin/env python3\nimport sys\n"));
}

#[test]
fn test_empty_console_script_flag_falls_back_to_guess() {
    let tmp = TempDir::new("empty_console_script_flag");
    let entry_points = tmp.path().join("entry_points.txt");
    fs::write(&entry_points, "[console_scripts]\nmy-tool = pkg.mod:main\n").unwrap();
    let out = tmp.path().join("out.py");

    let args: Vec<OsString> = vec![
        OsString::from("--console-script"),
        OsString::from(""),
        OsString::from("--console-script-guess"),
        OsString::from("my-tool"),
        OsString::from("--shebang"),
        OsString::from(""),
        entry_points.as_os_str().to_owned(),
        out.as_os_str().to_owned(),
    ];
    let opts = parse_options(&args);
    assert_eq!(opts.console_script, None);
    assert_eq!(opts.console_script_guess, "my-tool");
    assert_eq!(opts.shebang, "");

    run(&opts).expect("script should be generated");
    let got = fs::read_to_string(&out).unwrap();
    assert!(got.contains("from pkg.mod import main\n"));
    assert!(got.contains("sys.exit(main())"));
}

#[test]
fn test_equals_flag_syntax_and_flagfile() {
    let tmp = TempDir::new("flagfile");
    let entry_points = tmp.path().join("entry_points.txt");
    fs::write(&entry_points, "[console_scripts]\ncli = pkg.cli:run\n").unwrap();
    let out = tmp.path().join("out.py");
    let flagfile = tmp.path().join("args.params");
    fs::write(
        &flagfile,
        format!(
            "--console-script\n\n--console-script-guess=cli\n--shebang=#!/usr/bin/python3\n{}\n{}\n",
            entry_points.display(),
            out.display()
        ),
    )
    .unwrap();

    let opts = parse_options([format!("@{}", flagfile.display())]);
    assert_eq!(opts.console_script, None);
    run(&opts).expect("script should be generated");

    let got = fs::read_to_string(&out).unwrap();
    assert!(got.starts_with("#!/usr/bin/python3\nimport sys\n"));
    assert!(got.contains("from pkg.cli import run\n"));
}

#[test]
fn test_ini_colon_delimiter_comments_and_case_sensitivity() {
    let tmp = TempDir::new("ini_features");
    let entry_points = tmp.path().join("entry_points.txt");
    fs::write(
        &entry_points,
        "\
# Leading comment
; Semicolon comment

[other_section]
MyTool = wrong.mod:func

  [console_scripts]  
# Comment inside console_scripts
MyTool : correct.mod:Class.method
mytool = lower.mod:func

[trailing_section]
MyTool = trailing.mod:func
",
    )
    .unwrap();
    let out = tmp.path().join("out.py");

    run(&options(&entry_points, &out, Some("MyTool"), "", "")).expect("script should be generated");
    let got = fs::read_to_string(&out).unwrap();
    assert!(got.contains("from correct.mod import Class\n"));
    assert!(got.contains("sys.exit(Class.method())"));

    // Verify case-sensitive lookup fails for wrong case
    let err = run(&options(&entry_points, &out, Some("MYTOOL"), "", "")).unwrap_err();
    assert_eq!(
        err.to_string(),
        "The console_script 'MYTOOL' was not found, only the following are available: MyTool, mytool"
    );
}

#[test]
fn test_parse_console_scripts_edge_cases() {
    assert_eq!(parse_console_scripts(""), None);
    assert_eq!(
        parse_console_scripts("[console_scripts]\nempty_val = \n   indented = ignored:fn\n"),
        None
    );

    let parsed = parse_console_scripts(
        "\
[ console_scripts ]
alpha = pkg.a:first
  continuation_line_ignored
alpha = pkg.a:override
beta : pkg.b:run
empty_ignored =   
",
    )
    .expect("console_scripts section should be non-empty");

    assert_eq!(parsed.len(), 2);
    assert_eq!(
        parsed.get("alpha").map(String::as_str),
        Some("pkg.a:override")
    );
    assert_eq!(parsed.get("beta").map(String::as_str), Some("pkg.b:run"));
}

#[test]
fn test_nested_class_attribute_entry_point() {
    let tmp = TempDir::new("nested_attr");
    let entry_points = tmp.path().join("entry_points.txt");
    fs::write(
        &entry_points,
        "[console_scripts]\nrunner = pkg.sub.mod:Outer.Inner.execute\n",
    )
    .unwrap();
    let out = tmp.path().join("out.py");

    run(&options(&entry_points, &out, Some("runner"), "", "")).expect("script should be generated");
    let got = fs::read_to_string(&out).unwrap();
    assert!(got.contains("from pkg.sub.mod import Outer\n"));
    assert!(got.contains("sys.exit(Outer.Inner.execute())  # pyrefly: ignore[not-callable]\n"));
}

#[test]
fn test_help() {
    assert_eq!(
        parse_args(["--help"]).expect("--help should parse"),
        ParsedArgs::Help
    );
    assert_eq!(
        parse_args(["-h"]).expect("-h should parse"),
        ParsedArgs::Help
    );
    assert_eq!(run_cli(["--help"]), ExitCode::SUCCESS);
}

#[test]
fn test_cli_parse_errors_and_double_dash() {
    assert!(parse_args(["entry_points.txt", "out.py"]).is_err());
    assert!(parse_args(["--console-script-guess=foo", "only_one_positional"]).is_err());
    assert!(parse_args(["--console-script-guess=foo", "--unknown-flag", "a", "b"]).is_err());
    assert!(parse_args(["--console-script-guess=foo", "-x", "a", "b"]).is_err());
    assert!(parse_args(["--console-script"]).is_err());
    assert!(parse_args(["--console-script-guess"]).is_err());
    assert!(parse_args(["--shebang"]).is_err());

    let opts = parse_options([
        "--console-script-guess=foo",
        "--",
        "-dash_entry_points.txt",
        "-dash_out.py",
    ]);
    assert_eq!(opts.entry_points, PathBuf::from("-dash_entry_points.txt"));
    assert_eq!(opts.out, PathBuf::from("-dash_out.py"));
}

#[test]
fn test_run_cli_exit_codes() {
    let tmp = TempDir::new("run_cli");
    let entry_points = tmp.path().join("entry_points.txt");
    fs::write(&entry_points, "[console_scripts]\ncli = pkg.cli:main\n").unwrap();
    let out = tmp.path().join("cli_out.py");

    let code_ok = run_cli([
        OsString::from("--console-script-guess=cli"),
        entry_points.as_os_str().to_owned(),
        out.as_os_str().to_owned(),
    ]);
    assert_eq!(code_ok, ExitCode::SUCCESS);
    assert!(out.exists());

    let code_err = run_cli(["--unknown-flag"]);
    assert_eq!(code_err, ExitCode::FAILURE);
}

struct TempDir {
    path: PathBuf,
}

impl TempDir {
    fn new(prefix: &str) -> Self {
        let id = TEST_COUNTER.fetch_add(1, Ordering::SeqCst);
        let path = env::temp_dir().join(format!(
            "py_console_script_gen_test_{prefix}_{}_{id}",
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

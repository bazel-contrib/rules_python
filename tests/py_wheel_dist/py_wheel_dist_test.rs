use std::env;
use std::ffi::OsStr;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::atomic::{AtomicUsize, Ordering};

use py_wheel_dist_lib::{Options, ParsedArgs, create_wheel_dist, parse_args, run_cli};

static COUNTER: AtomicUsize = AtomicUsize::new(0);

struct TempDir {
    path: PathBuf,
}

impl TempDir {
    fn new(prefix: &str) -> Self {
        let id = COUNTER.fetch_add(1, Ordering::SeqCst);
        let path = env::temp_dir().join(format!(
            "py_wheel_dist_test_{}_{}_{}",
            prefix,
            std::process::id(),
            id
        ));
        fs::create_dir_all(&path).expect("temp dir should be creatable");
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

fn parse_options<I, T>(args: I) -> Options
where
    I: IntoIterator<Item = T>,
    T: Into<std::ffi::OsString>,
{
    match parse_args(args).expect("arguments should parse") {
        ParsedArgs::Options(opts) => opts,
        ParsedArgs::Help => panic!("unexpected --help"),
    }
}

#[test]
fn test_parse_args_space_separated() {
    let opts = parse_options([
        "--wheel",
        "path/to/foo.whl",
        "--name_file",
        "path/to/name.txt",
        "--output",
        "path/to/dist",
    ]);
    assert_eq!(
        opts,
        Options {
            wheel: PathBuf::from("path/to/foo.whl"),
            name_file: PathBuf::from("path/to/name.txt"),
            output: PathBuf::from("path/to/dist"),
        }
    );
}

#[test]
fn test_parse_args_equals_separated() {
    let opts = parse_options([
        "--wheel=path/to/foo.whl",
        "--name_file=path/to/name.txt",
        "--output=path/to/dist",
    ]);
    assert_eq!(
        opts,
        Options {
            wheel: PathBuf::from("path/to/foo.whl"),
            name_file: PathBuf::from("path/to/name.txt"),
            output: PathBuf::from("path/to/dist"),
        }
    );
}

#[test]
fn test_parse_args_help() {
    assert_eq!(
        parse_args(["--help"]).expect("--help should parse"),
        ParsedArgs::Help
    );
    assert_eq!(
        parse_args(["-h"]).expect("-h should parse"),
        ParsedArgs::Help
    );
}

#[test]
fn test_parse_args_flagfile() {
    let tmp = TempDir::new("flagfile");
    let flagfile = tmp.path().join("args.params");
    fs::write(
        &flagfile,
        "--wheel\nmy_wheel.whl\n--name_file=my_name.txt\n--output\nout_dir\n",
    )
    .expect("flagfile should be writable");

    let opts = parse_options([format!("@{}", flagfile.display())]);
    assert_eq!(
        opts,
        Options {
            wheel: PathBuf::from("my_wheel.whl"),
            name_file: PathBuf::from("my_name.txt"),
            output: PathBuf::from("out_dir"),
        }
    );
}

#[test]
fn test_parse_args_mixed_flagfile_and_overrides() {
    let tmp = TempDir::new("mixed_flagfile");
    let flagfile = tmp.path().join("args.params");
    fs::write(&flagfile, "--wheel\nfirst.whl\n--name_file\nname.txt\n")
        .expect("flagfile should be writable");

    let flagfile_arg = format!("@{}", flagfile.display());
    let opts = parse_options([
        flagfile_arg.as_str(),
        "--wheel=override.whl",
        "--output",
        "final_out",
    ]);
    assert_eq!(
        opts,
        Options {
            wheel: PathBuf::from("override.whl"),
            name_file: PathBuf::from("name.txt"),
            output: PathBuf::from("final_out"),
        }
    );
}

#[test]
fn test_parse_args_missing_required_flags() {
    let err_no_wheel =
        parse_args(["--name_file", "a", "--output", "b"]).expect_err("missing --wheel should fail");
    assert!(
        err_no_wheel.to_string().contains("--wheel"),
        "got: {err_no_wheel:#}"
    );

    let err_no_name =
        parse_args(["--wheel", "a", "--output", "b"]).expect_err("missing --name_file should fail");
    assert!(
        err_no_name.to_string().contains("--name_file"),
        "got: {err_no_name:#}"
    );

    let err_no_out =
        parse_args(["--wheel", "a", "--name_file", "b"]).expect_err("missing --output should fail");
    assert!(
        err_no_out.to_string().contains("--output"),
        "got: {err_no_out:#}"
    );
}

#[test]
fn test_parse_args_missing_flag_values_and_unknown_args() {
    assert!(parse_args(["--wheel"]).is_err());
    assert!(parse_args(["--name_file"]).is_err());
    assert!(parse_args(["--output"]).is_err());
    assert!(parse_args(["--unknown", "val"]).is_err());
    assert!(parse_args(["-x"]).is_err());
    assert!(parse_args(["positional_arg"]).is_err());
    assert!(parse_args(["@nonexistent_flagfile_path_12345"]).is_err());
}

#[test]
fn test_copy_wheel_into_new_and_existing_output_directory() {
    let tmp = TempDir::new("copy");
    let wheel_path = tmp.path().join("input.whl");
    let name_file_path = tmp.path().join("name.txt");
    let out_dir = tmp.path().join("nested").join("dist_out");

    let wheel_bytes = b"PK\x03\x04fake-wheel-archive-bytes";
    fs::write(&wheel_path, wheel_bytes).expect("wheel should be writable");
    fs::write(&name_file_path, "  my_pkg-0.1.0-py3-none-any.whl\n")
        .expect("name file should be writable");

    // 1. Copy into a new (non-existent) nested output directory; the name is trimmed.
    let copied_path = create_wheel_dist(&wheel_path, &name_file_path, &out_dir)
        .expect("copy into a new directory should succeed");
    assert_eq!(copied_path, out_dir.join("my_pkg-0.1.0-py3-none-any.whl"));
    assert_eq!(
        fs::read(&copied_path).expect("copied wheel should be readable"),
        wheel_bytes
    );

    // 2. Copy into an already-existing output directory with updated wheel content.
    let updated_bytes = b"PK\x03\x04updated-wheel-archive-bytes";
    fs::write(&wheel_path, updated_bytes).expect("wheel should be writable");
    fs::write(&name_file_path, "my_pkg-0.2.0-py3-none-any.whl")
        .expect("name file should be writable");

    let second_path = create_wheel_dist(&wheel_path, &name_file_path, &out_dir)
        .expect("copy into an existing directory should succeed");
    assert_eq!(second_path, out_dir.join("my_pkg-0.2.0-py3-none-any.whl"));
    assert_eq!(
        fs::read(&second_path).expect("copied wheel should be readable"),
        updated_bytes
    );

    // 3. Verify run_cli returns ExitCode::SUCCESS and ExitCode::FAILURE.
    assert_eq!(
        run_cli([
            OsStr::new("--wheel"),
            wheel_path.as_os_str(),
            OsStr::new("--name_file"),
            name_file_path.as_os_str(),
            OsStr::new("--output"),
            out_dir.as_os_str(),
        ]),
        ExitCode::SUCCESS
    );
    assert_eq!(run_cli(["--help"]), ExitCode::SUCCESS);
    assert_eq!(run_cli(["--unknown"]), ExitCode::FAILURE);
}

#[test]
fn test_error_handling_missing_inputs() {
    let tmp = TempDir::new("errors");
    let wheel_path = tmp.path().join("input.whl");
    let name_file_path = tmp.path().join("name.txt");
    let out_dir = tmp.path().join("dist");

    // Missing both files.
    assert!(create_wheel_dist(&wheel_path, &name_file_path, &out_dir).is_err());

    // Present name_file, missing wheel file.
    fs::write(&name_file_path, "pkg-0.1.0-py3-none-any.whl").expect("name file should be writable");
    assert!(create_wheel_dist(&wheel_path, &name_file_path, &out_dir).is_err());
}

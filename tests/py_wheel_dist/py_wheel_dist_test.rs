use std::env;
use std::ffi::OsStr;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::atomic::{AtomicUsize, Ordering};

use py_wheel_dist_lib::{
    Options, create_wheel_dist, parse_args, run, run_cli, validate_wheel_name,
};

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

#[test]
fn test_parse_args_space_separated() {
    let args = [
        "--wheel",
        "path/to/foo.whl",
        "--name_file",
        "path/to/name.txt",
        "--output",
        "path/to/dist",
    ];
    let opts = parse_args(args).unwrap();
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
    let args = [
        "--wheel=path/to/foo.whl",
        "--name_file=path/to/name.txt",
        "--output=path/to/dist",
    ];
    let opts = parse_args(args).unwrap();
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
fn test_parse_args_flagfile() {
    let tmp = TempDir::new("flagfile");
    let flagfile = tmp.path().join("args.params");
    fs::write(
        &flagfile,
        "--wheel\n\nmy_wheel.whl\n--name_file=my_name.txt\n\n--output\nout_dir\n",
    )
    .unwrap();

    let arg = format!("@{}", flagfile.display());
    let opts = parse_args([arg]).unwrap();
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
    fs::write(&flagfile, "--wheel\nfirst.whl\n--name_file\nname.txt\n").unwrap();

    let flagfile_arg = format!("@{}", flagfile.display());
    let opts = parse_args([
        flagfile_arg.as_str(),
        "--wheel=override.whl",
        "--output",
        "final_out",
    ])
    .unwrap();
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
    let err_no_wheel = parse_args(["--name_file", "a", "--output", "b"]).unwrap_err();
    assert!(err_no_wheel.contains("--wheel"), "got: {err_no_wheel}");

    let err_no_name = parse_args(["--wheel", "a", "--output", "b"]).unwrap_err();
    assert!(err_no_name.contains("--name_file"), "got: {err_no_name}");

    let err_no_out = parse_args(["--wheel", "a", "--name_file", "b"]).unwrap_err();
    assert!(err_no_out.contains("--output"), "got: {err_no_out}");
}

#[test]
fn test_parse_args_missing_flag_values_and_unknown_args() {
    assert!(parse_args(["--wheel"]).is_err());
    assert!(parse_args(["--name_file"]).is_err());
    assert!(parse_args(["--output"]).is_err());
    assert!(parse_args(["--wheel="]).is_err());
    assert!(parse_args(["--name_file="]).is_err());
    assert!(parse_args(["--output="]).is_err());
    assert!(parse_args(["--unknown", "val"]).is_err());
    let bogus_err = parse_args(["--bogus-flag=123"]).unwrap_err();
    assert!(
        bogus_err.contains("unexpected argument: --bogus-flag=123"),
        "got: {bogus_err}"
    );
    assert!(parse_args(["positional_arg"]).is_err());
    assert!(parse_args(["@"]).is_err());
    assert!(parse_args(["@nonexistent_flagfile_path_12345"]).is_err());
}

#[test]
fn test_validate_wheel_name() {
    assert_eq!(
        validate_wheel_name("example_pkg-0.0.1-py3-none-any.whl").unwrap(),
        "example_pkg-0.0.1-py3-none-any.whl"
    );
    assert_eq!(
        validate_wheel_name("  \n\t example_pkg-1.2.3-py3-none-any.whl \r\n ").unwrap(),
        "example_pkg-1.2.3-py3-none-any.whl"
    );

    assert!(validate_wheel_name("").is_err());
    assert!(validate_wheel_name("   \n\t  ").is_err());
    assert!(validate_wheel_name(".").is_err());
    assert!(validate_wheel_name("..").is_err());
    assert!(validate_wheel_name("../evil.whl").is_err());
    assert!(validate_wheel_name("sub/wheel.whl").is_err());
    assert!(validate_wheel_name("sub\\wheel.whl").is_err());
}

#[test]
fn test_copy_wheel_into_new_and_existing_output_directory() {
    let tmp = TempDir::new("copy");
    let wheel_path = tmp.path().join("input.whl");
    let name_file_path = tmp.path().join("name.txt");
    let out_dir = tmp.path().join("nested").join("dist_out");

    let wheel_bytes = b"PK\x03\x04fake-wheel-archive-bytes";
    fs::write(&wheel_path, wheel_bytes).unwrap();
    fs::write(&name_file_path, "  my_pkg-0.1.0-py3-none-any.whl\n").unwrap();

    // 1. Copy into a new (non-existent) nested output directory.
    let opts = Options {
        wheel: wheel_path.clone(),
        name_file: name_file_path.clone(),
        output: out_dir.clone(),
    };
    let copied_path = run(&opts).unwrap();
    assert_eq!(copied_path, out_dir.join("my_pkg-0.1.0-py3-none-any.whl"));
    assert_eq!(fs::read(&copied_path).unwrap(), wheel_bytes);

    // 2. Copy into an already-existing output directory with updated wheel content.
    let updated_bytes = b"PK\x03\x04updated-wheel-archive-bytes";
    fs::write(&wheel_path, updated_bytes).unwrap();
    fs::write(&name_file_path, "my_pkg-0.2.0-py3-none-any.whl").unwrap();

    let second_path = create_wheel_dist(&wheel_path, &name_file_path, &out_dir).unwrap();
    assert_eq!(second_path, out_dir.join("my_pkg-0.2.0-py3-none-any.whl"));
    assert_eq!(fs::read(&second_path).unwrap(), updated_bytes);

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
    assert_eq!(run_cli(["--unknown"]), ExitCode::FAILURE);
}

#[test]
fn test_error_handling_missing_inputs_and_invalid_name() {
    let tmp = TempDir::new("errors");
    let wheel_path = tmp.path().join("input.whl");
    let name_file_path = tmp.path().join("name.txt");
    let out_dir = tmp.path().join("dist");

    // Missing both files.
    assert!(create_wheel_dist(&wheel_path, &name_file_path, &out_dir).is_err());

    // Present name_file, missing wheel file.
    fs::write(&name_file_path, "pkg-0.1.0-py3-none-any.whl").unwrap();
    assert!(create_wheel_dist(&wheel_path, &name_file_path, &out_dir).is_err());

    // Present wheel file, empty/whitespace name_file.
    fs::write(&wheel_path, b"wheel-data").unwrap();
    fs::write(&name_file_path, "   \n ").unwrap();
    assert!(create_wheel_dist(&wheel_path, &name_file_path, &out_dir).is_err());

    // Invalid traversal name in name_file.
    fs::write(&name_file_path, "../escape.whl").unwrap();
    assert!(create_wheel_dist(&wheel_path, &name_file_path, &out_dir).is_err());
}

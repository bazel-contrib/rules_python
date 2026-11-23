//! Unified `shrubbery` ("Shell replacements for Bazel build tools in Rust") subcommand
//! dispatcher for `@rules_python` Rust build tools.

// Errors must be returned, not panicked; see the `rust-lint` config in .bazelrc.
#![deny(clippy::expect_used, clippy::unwrap_used)]

use std::ffi::OsString;
use std::process::ExitCode;

/// Subcommand name constants supported by `shrubbery`.
pub mod subcommands {
    // keep-sorted start case=no
    pub const BUILD_DATA_WRITER: &str = "build_data_writer";
    pub const EXE_ZIP_MAKER: &str = "exe_zip_maker";
    pub const EXTRACT_WHEEL_FILES: &str = "extract_wheel_files";
    pub const PY_CONSOLE_SCRIPT_GEN: &str = "py_console_script_gen";
    pub const PY_TEST_MAIN_VALIDATOR: &str = "py_test_main_validator";
    pub const PY_WHEEL_DIST: &str = "py_wheel_dist";
    pub const VENV_SHEBANG_REWRITER: &str = "venv_shebang_rewriter";
    pub const WHEEL_RECORD_REWRITER: &str = "wheel_record_rewriter";
    pub const WHEELMAKER: &str = "wheelmaker";
    pub const ZIP_MAIN_MAKER: &str = "zip_main_maker";
    pub const ZIPPER: &str = "zipper";
    // keep-sorted end
}

/// Canonical subcommand names supported by `shrubbery`.
pub const SUBCOMMANDS: &[&str] = &[
    // keep-sorted start case=no
    subcommands::BUILD_DATA_WRITER,
    subcommands::EXE_ZIP_MAKER,
    subcommands::EXTRACT_WHEEL_FILES,
    subcommands::PY_CONSOLE_SCRIPT_GEN,
    subcommands::PY_TEST_MAIN_VALIDATOR,
    subcommands::PY_WHEEL_DIST,
    subcommands::VENV_SHEBANG_REWRITER,
    subcommands::WHEEL_RECORD_REWRITER,
    subcommands::WHEELMAKER,
    subcommands::ZIP_MAIN_MAKER,
    subcommands::ZIPPER,
    // keep-sorted end
];

fn print_usage(prog_name: &str, to_stderr: bool) {
    let msg = format!(
        "shrubbery — A nice, two-level effect with a little path running down the middle.\n\nUsage: {} <subcommand> [args...]\n\nAvailable subcommands:\n  {}",
        prog_name,
        SUBCOMMANDS.join("\n  ")
    );
    if to_stderr {
        eprintln!("{}", msg);
    } else {
        println!("{}", msg);
    }
}

/// Dispatches CLI arguments (including `argv[0]`) to the requested subcommand and returns the
/// process exit code.
pub fn run_cli<I, T>(args: I) -> ExitCode
where
    I: IntoIterator<Item = T>,
    T: Into<OsString>,
{
    let mut iter = args.into_iter().map(Into::into);
    let prog_name = iter
        .next()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| "shrubbery".to_string());

    let Some(sub_os) = iter.next() else {
        print_usage(&prog_name, true);
        return ExitCode::FAILURE;
    };
    let sub_raw = sub_os.to_string_lossy();
    if sub_raw == "-h" || sub_raw == "--help" || sub_raw == "help" {
        print_usage(&prog_name, false);
        return ExitCode::SUCCESS;
    }

    match sub_raw.as_ref() {
        // keep-sorted start case=no
        subcommands::BUILD_DATA_WRITER => build_data_writer_lib::run_cli(iter),
        subcommands::EXE_ZIP_MAKER => exe_zip_maker_lib::run_cli(iter),
        subcommands::EXTRACT_WHEEL_FILES => extract_wheel_files_lib::run_cli(iter),
        subcommands::PY_CONSOLE_SCRIPT_GEN => py_console_script_gen_lib::run_cli(iter),
        subcommands::PY_TEST_MAIN_VALIDATOR => py_test_main_validator_lib::run_cli(iter),
        subcommands::PY_WHEEL_DIST => py_wheel_dist_lib::run_cli(iter),
        subcommands::VENV_SHEBANG_REWRITER => venv_shebang_rewriter_lib::run_cli(iter),
        subcommands::WHEEL_RECORD_REWRITER => wheel_record_rewriter_lib::run_cli(iter),
        subcommands::WHEELMAKER => wheelmaker_lib::run_cli(iter),
        subcommands::ZIP_MAIN_MAKER => zip_main_maker_lib::run_cli(iter),
        subcommands::ZIPPER => zipper_lib::run_cli(iter),
        // keep-sorted end
        _ => {
            eprintln!("shrubbery: error: unknown subcommand '{}'", sub_raw);
            print_usage(&prog_name, true);
            ExitCode::FAILURE
        }
    }
}

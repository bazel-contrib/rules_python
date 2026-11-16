//! Library for generating the output directory for `py_wheel_dist`.
//!
//! Reads the canonical wheel filename from `--name_file` (UTF-8, whitespace-trimmed),
//! creates the `--output` directory, and copies `--wheel` to `<output>/<wheel_name>`.

// Errors must be returned, not panicked; see the `rust-lint` config in .bazelrc.
#![deny(clippy::expect_used, clippy::unwrap_used)]

use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use anyhow::{Context, Result, bail};
use lexopt::prelude::*;

mod flags {
    // keep-sorted start
    pub const HELP: &str = "help";
    pub const HELP_SHORT: char = 'h';
    pub const NAME_FILE: &str = "name_file";
    pub const OUTPUT: &str = "output";
    pub const WHEEL: &str = "wheel";
    // keep-sorted end
}

/// Usage text for `--help`. `lexopt` does not generate help, so this is maintained by hand.
const USAGE: &str = "\
Usage: py_wheel_dist --wheel <PATH> --name_file <PATH> --output <PATH>

Copy a wheel into a dist directory under its canonical filename.

Options:
  --wheel <PATH>       Path to the wheel to copy
  --name_file <PATH>   File containing the sanitized wheel filename
  --output <PATH>      Output directory to copy the wheel into
  @<FLAGFILE>          Read newline-delimited arguments from <FLAGFILE>
  -h, --help           Print this help";

/// Creates the output directory and copies the wheel file to `<output>/<wheel_name>`, where
/// `wheel_name` is the whitespace-trimmed content of `name_file_path`.
pub fn create_wheel_dist(
    wheel_path: &Path,
    name_file_path: &Path,
    output_dir: &Path,
) -> Result<PathBuf> {
    let raw_name = fs::read_to_string(name_file_path)
        .with_context(|| format!("reading {}", name_file_path.display()))?;
    let wheel_name = raw_name.trim();

    fs::create_dir_all(output_dir).with_context(|| format!("creating {}", output_dir.display()))?;

    let destination = output_dir.join(wheel_name);
    fs::copy(wheel_path, &destination).with_context(|| {
        format!(
            "copying {} to {}",
            wheel_path.display(),
            destination.display()
        )
    })?;
    Ok(destination)
}

/// Parsed command-line options for `py_wheel_dist`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Options {
    /// Path to the input `.whl` file.
    pub wheel: PathBuf,
    /// Path to the file containing the canonical wheel filename.
    pub name_file: PathBuf,
    /// Path to the output directory where the wheel should be copied.
    pub output: PathBuf,
}

/// Result of parsing the command line.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Cli {
    /// `--help` was requested.
    Help,
    /// Copy the wheel with the given options.
    Run(Options),
}

/// Parses command-line arguments (excluding `argv[0]` and subcommand name) into [`Cli`].
pub fn parse_args<I, T>(args: I) -> Result<Cli>
where
    I: IntoIterator<Item = T>,
    T: Into<OsString>,
{
    let expanded = argfile::expand_args_from(
        args.into_iter().map(Into::into),
        argfile::parse_fromfile,
        argfile::PREFIX,
    )
    .context("reading @flagfile")?;

    let mut wheel: Option<PathBuf> = None;
    let mut name_file: Option<PathBuf> = None;
    let mut output: Option<PathBuf> = None;

    let mut parser = lexopt::Parser::from_args(expanded);
    while let Some(arg) = parser.next()? {
        match arg {
            Short(flags::HELP_SHORT) | Long(flags::HELP) => return Ok(Cli::Help),
            Long(flags::WHEEL) => {
                wheel = Some(PathBuf::from(parser.value()?));
            }
            Long(flags::NAME_FILE) => {
                name_file = Some(PathBuf::from(parser.value()?));
            }
            Long(flags::OUTPUT) => {
                output = Some(PathBuf::from(parser.value()?));
            }
            _ => bail!("{}", arg.unexpected()),
        }
    }

    let wheel = wheel.with_context(|| format!("missing required argument: --{}", flags::WHEEL))?;
    let name_file =
        name_file.with_context(|| format!("missing required argument: --{}", flags::NAME_FILE))?;
    let output =
        output.with_context(|| format!("missing required argument: --{}", flags::OUTPUT))?;

    Ok(Cli::Run(Options {
        wheel,
        name_file,
        output,
    }))
}

/// Parses CLI arguments (excluding `argv[0]` and subcommand name), populates the wheel dist
/// directory, and returns the process exit code.
pub fn run_cli<I, T>(args: I) -> ExitCode
where
    I: IntoIterator<Item = T>,
    T: Into<OsString>,
{
    let options = match parse_args(args) {
        Ok(Cli::Help) => {
            println!("{USAGE}");
            return ExitCode::SUCCESS;
        }
        Ok(Cli::Run(opts)) => opts,
        Err(err) => {
            eprintln!("py_wheel_dist: error: {err:#}");
            return ExitCode::FAILURE;
        }
    };
    if let Err(err) = create_wheel_dist(&options.wheel, &options.name_file, &options.output) {
        eprintln!("py_wheel_dist: error: {err:#}");
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}

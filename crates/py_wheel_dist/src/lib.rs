//! Library for generating the output directory for `py_wheel_dist`.
//!
//! Usage:
//!   `py_wheel_dist --wheel <path> --name_file <path> --output <path>`
//!
//! Reads the canonical wheel filename from `--name_file` (UTF-8, whitespace-trimmed),
//! creates the `--output` directory, and copies `--wheel` to `<output>/<wheel_name>`.

use std::ffi::OsString;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

/// Validates and trims the wheel filename read from `--name_file`.
///
/// Ensures the trimmed name is non-empty and a valid single file basename without
/// path separators (`/`, `\`) or parent directory traversal (`..`).
pub fn validate_wheel_name(raw_name: &str) -> io::Result<&str> {
    let trimmed = raw_name.trim();
    if trimmed.is_empty() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "wheel name in --name_file is empty",
        ));
    }
    if trimmed == "."
        || trimmed == ".."
        || trimmed.contains('/')
        || trimmed.contains('\\')
        || trimmed.contains("..")
        || trimmed.contains('\0')
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("invalid wheel filename in --name_file: '{trimmed}'"),
        ));
    }
    Ok(trimmed)
}

/// Creates the output directory and copies the wheel file to `<output>/<wheel_name>`.
pub fn create_wheel_dist(
    wheel_path: &Path,
    name_file_path: &Path,
    output_dir: &Path,
) -> io::Result<PathBuf> {
    let raw_name = fs::read_to_string(name_file_path)?;
    let wheel_name = validate_wheel_name(&raw_name)?;

    fs::create_dir_all(output_dir)?;

    let destination = output_dir.join(wheel_name);
    fs::copy(wheel_path, &destination)?;
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

fn parse_flagfile(content: &str, prefix: char) -> Vec<argfile::Argument> {
    content
        .lines()
        .filter(|line| !line.is_empty())
        .map(|line| argfile::Argument::parse_ref(line, prefix))
        .collect()
}

fn parse_non_empty_path(parser: &mut lexopt::Parser, flag: &str) -> Result<PathBuf, String> {
    let val = parser.value().map_err(|e| e.to_string())?;
    if val.is_empty() {
        return Err(format!("empty value for {flag}"));
    }
    Ok(PathBuf::from(val))
}

/// Parses command-line arguments (excluding `argv[0]`) into [`Options`].
///
/// Supports `--flag value`, `--flag=value`, and `@flagfile` argument expansion.
pub fn parse_args<I, T>(args: I) -> Result<Options, String>
where
    I: IntoIterator<Item = T>,
    T: Into<OsString>,
{
    use lexopt::prelude::*;

    let raw_args: Vec<OsString> = args.into_iter().map(Into::into).collect();
    if raw_args.iter().any(|arg| arg == "@") {
        return Err("empty @flagfile path".to_string());
    }
    let expanded = argfile::expand_args_from(raw_args.into_iter(), parse_flagfile, argfile::PREFIX)
        .map_err(|e| format!("failed to read flagfile: {e}"))?;

    let mut wheel = None;
    let mut name_file = None;
    let mut output = None;

    let mut parser = lexopt::Parser::from_args(expanded);
    while let Some(arg) = parser.next().map_err(|e| e.to_string())? {
        match arg {
            Short('h') | Long("help") => {
                return Err(
                    "Usage: py_wheel_dist --wheel <path> --name_file <path> --output <path>"
                        .to_string(),
                );
            }
            Long("wheel") => wheel = Some(parse_non_empty_path(&mut parser, "--wheel")?),
            Long("name_file") => {
                name_file = Some(parse_non_empty_path(&mut parser, "--name_file")?);
            }
            Long("output") => output = Some(parse_non_empty_path(&mut parser, "--output")?),
            Long(other) => {
                let other = other.to_owned();
                if let Some(val) = parser.optional_value() {
                    return Err(format!(
                        "unexpected argument: --{other}={}",
                        val.to_string_lossy()
                    ));
                }
                return Err(format!("unexpected argument: --{other}"));
            }
            Short(ch) => {
                if let Some(val) = parser.optional_value() {
                    return Err(format!(
                        "unexpected argument: -{ch}{}",
                        val.to_string_lossy()
                    ));
                }
                return Err(format!("unexpected argument: -{ch}"));
            }
            Value(val) => {
                return Err(format!("unexpected argument: {}", val.to_string_lossy()));
            }
        }
    }

    let wheel = wheel.ok_or_else(|| "missing required argument: --wheel".to_string())?;
    let name_file =
        name_file.ok_or_else(|| "missing required argument: --name_file".to_string())?;
    let output = output.ok_or_else(|| "missing required argument: --output".to_string())?;

    Ok(Options {
        wheel,
        name_file,
        output,
    })
}

/// Executes `py_wheel_dist` with the parsed [`Options`].
pub fn run(options: &Options) -> io::Result<PathBuf> {
    create_wheel_dist(&options.wheel, &options.name_file, &options.output)
}

/// Parses CLI arguments (excluding `argv[0]` and subcommand name), populates the wheel dist
/// directory, and returns the process exit code.
pub fn run_cli<I, T>(args: I) -> ExitCode
where
    I: IntoIterator<Item = T>,
    T: Into<OsString>,
{
    let options = match parse_args(args) {
        Ok(opts) => opts,
        Err(msg) => {
            eprintln!("py_wheel_dist: error: {msg}");
            return ExitCode::FAILURE;
        }
    };
    if let Err(err) = run(&options) {
        eprintln!("py_wheel_dist: error: {err}");
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}

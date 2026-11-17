//! Library for writing Bazel target build data and workspace status stamping info.
//!
//! Configuration is read from the environment variables `OUTPUT`, `TARGET`, `STAMPED`,
//! `VERSION_FILE`, and `INFO_FILE`, matching the `build_data_writer.sh` script it replaces.
//! The command line accepts no arguments other than `-h`/`--help`.

// Errors must be returned, not panicked; see the `rust-lint` config in .bazelrc.
#![deny(clippy::expect_used, clippy::unwrap_used)]

use std::env;
use std::ffi::OsString;
use std::fs::{self, File};
use std::io::{BufWriter, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use anyhow::{Context, Result, bail};
use lexopt::prelude::*;

mod flags {
    // keep-sorted start
    pub const HELP: &str = "help";
    pub const HELP_SHORT: char = 'h';
    // keep-sorted end
}

/// Environment variables consumed by the tool.
mod env_vars {
    // keep-sorted start
    pub const INFO_FILE: &str = "INFO_FILE";
    pub const OUTPUT: &str = "OUTPUT";
    pub const STAMPED: &str = "STAMPED";
    pub const TARGET: &str = "TARGET";
    pub const VERSION_FILE: &str = "VERSION_FILE";
    // keep-sorted end
}

/// Usage text for `--help`. `lexopt` does not generate help, so this is maintained by hand.
const USAGE: &str = "\
Usage: build_data_writer

Write a build_data.txt file describing a target and its workspace status.
All configuration comes from environment variables; no arguments are accepted.

Environment variables:
  OUTPUT         Path of the build data file to write (required)
  TARGET         Label of the target being built (required)
  STAMPED        TRUE or FALSE; whether workspace status stamping is enabled (required)
  VERSION_FILE   Path to volatile-status.txt to append; ignored when empty
  INFO_FILE      Path to stable-status.txt to append; ignored when empty

Options:
  -h, --help     Print this help";

/// Writes the build data file according to `options`.
///
/// # Errors
///
/// Returns an error when the output file cannot be created or written, or when a configured
/// status file cannot be read.
pub fn write_build_data(options: &Options) -> Result<()> {
    let file = File::create(&options.output)
        .with_context(|| format!("creating {}", options.output.display()))?;
    let mut writer = BufWriter::new(file);

    writeln!(writer, "TARGET {}", options.target)?;
    writeln!(
        writer,
        "STAMPED {}",
        if options.stamped { "TRUE" } else { "FALSE" }
    )?;

    if let Some(version_file) = &options.version_file {
        append_status_file(&mut writer, version_file)?;
    }
    if let Some(info_file) = &options.info_file {
        append_status_file(&mut writer, info_file)?;
    }

    writer
        .flush()
        .with_context(|| format!("writing {}", options.output.display()))
}

fn append_status_file<W: Write>(writer: &mut W, path: &Path) -> Result<()> {
    let contents = fs::read(path).with_context(|| format!("reading {}", path.display()))?;
    writer.write_all(&contents)?;
    if !contents.is_empty() && !contents.ends_with(b"\n") {
        writer.write_all(b"\n")?;
    }
    Ok(())
}

fn parse_stamped(val: &str) -> Result<bool> {
    match val {
        "TRUE" => Ok(true),
        "FALSE" => Ok(false),
        other => bail!("{} must be TRUE or FALSE, got '{other}'", env_vars::STAMPED),
    }
}

fn required_env<F>(get_env: &F, key: &str) -> Result<String>
where
    F: Fn(&str) -> Option<OsString>,
{
    get_env(key)
        .with_context(|| format!("missing required environment variable: {key}"))?
        .into_string()
        .map_err(|raw| anyhow::anyhow!("{key} environment variable is not valid UTF-8: {raw:?}"))
}

/// Parses command-line arguments (excluding `argv[0]` and subcommand name) and the environment
/// provided by `get_env` into [`ParsedArgs`].
///
/// # Errors
///
/// Returns an error when an argument other than `-h`/`--help` is given, when `OUTPUT`, `TARGET`,
/// or `STAMPED` is unset, or when `STAMPED` is neither `TRUE` nor `FALSE`.
pub fn parse_env_and_args<I, T, F>(args: I, get_env: F) -> Result<ParsedArgs>
where
    I: IntoIterator<Item = T>,
    T: Into<OsString>,
    F: Fn(&str) -> Option<OsString>,
{
    let mut parser = lexopt::Parser::from_args(args.into_iter().map(Into::into));
    if let Some(arg) = parser.next()? {
        match arg {
            Short(flags::HELP_SHORT) | Long(flags::HELP) => return Ok(ParsedArgs::Help),
            _ => bail!("{}", arg.unexpected()),
        }
    }

    let output = get_env(env_vars::OUTPUT)
        .map(PathBuf::from)
        .with_context(|| {
            format!(
                "missing required environment variable: {}",
                env_vars::OUTPUT
            )
        })?;
    let target = required_env(&get_env, env_vars::TARGET)?;
    let stamped = parse_stamped(&required_env(&get_env, env_vars::STAMPED)?)?;
    let version_file = get_env(env_vars::VERSION_FILE)
        .filter(|s| !s.is_empty())
        .map(PathBuf::from);
    let info_file = get_env(env_vars::INFO_FILE)
        .filter(|s| !s.is_empty())
        .map(PathBuf::from);

    Ok(ParsedArgs::Options(Options {
        output,
        target,
        stamped,
        version_file,
        info_file,
    }))
}

/// Parses command-line arguments (excluding `argv[0]` and subcommand name) and the process
/// environment into [`ParsedArgs`].
///
/// # Errors
///
/// See [`parse_env_and_args`].
pub fn parse_args<I, T>(args: I) -> Result<ParsedArgs>
where
    I: IntoIterator<Item = T>,
    T: Into<OsString>,
{
    parse_env_and_args(args, |key| env::var_os(key))
}

/// Parses CLI arguments (excluding `argv[0]` and subcommand name) and the process environment,
/// writes the build data file, and returns the process exit code.
pub fn run_cli<I, T>(args: I) -> ExitCode
where
    I: IntoIterator<Item = T>,
    T: Into<OsString>,
{
    let options = match parse_args(args) {
        Ok(ParsedArgs::Help) => {
            println!("{USAGE}");
            return ExitCode::SUCCESS;
        }
        Ok(ParsedArgs::Options(opts)) => opts,
        Err(err) => {
            eprintln!("build_data_writer: error: {err:#}");
            return ExitCode::FAILURE;
        }
    };
    if let Err(err) = write_build_data(&options) {
        eprintln!("build_data_writer: error: {err:#}");
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}

/// Result of parsing command-line arguments and the environment.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ParsedArgs {
    /// `--help` was requested.
    Help,
    /// Parsed command-line and environment options.
    Options(Options),
}

/// Configuration options for writing a `build_data.txt` file.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Options {
    /// Path to the output `build_data.txt` file, relative to the current working directory or
    /// absolute.
    pub output: PathBuf,
    /// Target label string (e.g. `//pkg:target`).
    pub target: String,
    /// Whether stamping is enabled.
    pub stamped: bool,
    /// Optional path to Bazel's `volatile-status.txt` (`ctx.version_file`), relative to the
    /// current working directory or absolute.
    pub version_file: Option<PathBuf>,
    /// Optional path to Bazel's `stable-status.txt` (`ctx.info_file`), relative to the current
    /// working directory or absolute.
    pub info_file: Option<PathBuf>,
}

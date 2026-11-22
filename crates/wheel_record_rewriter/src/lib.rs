//! Rewrites a wheel's `RECORD` file to reflect its final installed layout.
//!
//! PEP 427 specifies archive filenames are UTF-8, and while the encoding of `dist-info` files
//! isn't formally standardized in PEP 376, packaging tools like `pip` and `importlib.metadata`
//! treat them as UTF-8 in practice.
//! See: <https://discuss.python.org/t/encoding-of-files-in-the-dist-info-directory/6734/4>

// Errors must be returned, not panicked; see the `rust-lint` config in .bazelrc.
#![deny(clippy::expect_used, clippy::unwrap_used)]

use std::collections::HashSet;
use std::ffi::OsString;
use std::fs::File;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use anyhow::{Context, Result, anyhow, bail};
use lexopt::prelude::*;

mod flags {
    // keep-sorted start
    pub const HELP: &str = "help";
    pub const HELP_SHORT: char = 'h';
    // keep-sorted end
}

/// Usage text for `--help`. `lexopt` does not generate help, so this is maintained by hand.
const USAGE: &str = "\
Usage: wheel_record_rewriter <IN_PATH> <OUT_PATH> <TARGET_OS> <DATA_DIR_BASENAME> [REWRITTEN_SCRIPT...]

Rewrite a wheel RECORD file to reflect its final installed layout.

Arguments:
  <IN_PATH>              Path to the original RECORD file
  <OUT_PATH>             Path to write the rewritten RECORD file
  <TARGET_OS>            Target layout: `unix` or `windows`
  <DATA_DIR_BASENAME>    Basename of the wheel's `.data` directory
  [REWRITTEN_SCRIPT...]  Script names that had shebang rewriting applied (get a `.bat` suffix on Windows)

Options:
  -h, --help             Print this help";

fn rewrite_entry_path_with_prefixes(
    entry_path: &str,
    target_os: TargetOs,
    data_prefix: &str,
    prefixes: &ReplacementPrefixes,
    rewritten_scripts: &HashSet<String>,
) -> String {
    let Some(rest) = entry_path.strip_prefix(data_prefix) else {
        return entry_path.to_owned();
    };

    if let Some(after) = rest.strip_prefix("purelib/") {
        format!("{}{after}", prefixes.purelib_repl)
    } else if let Some(after) = rest.strip_prefix("platlib/") {
        format!("{}{after}", prefixes.platlib_repl)
    } else if let Some(spath) = rest.strip_prefix("scripts/") {
        if target_os == TargetOs::Windows && rewritten_scripts.contains(spath) {
            format!("{}{spath}.bat", prefixes.scripts_repl)
        } else {
            format!("{}{spath}", prefixes.scripts_repl)
        }
    } else if let Some(after) = rest.strip_prefix("headers/") {
        format!("{}{after}", prefixes.headers_repl)
    } else if let Some(after) = rest.strip_prefix("data/") {
        format!("{}{after}", prefixes.data_repl)
    } else {
        entry_path.to_owned()
    }
}

/// Rewrites a single unescaped `RECORD` entry path (column 0).
pub fn rewrite_entry_path(
    entry_path: &str,
    target_os: TargetOs,
    data_dir_basename: &str,
    rewritten_scripts: &HashSet<String>,
) -> String {
    let data_prefix = format!("{data_dir_basename}/");
    let prefixes = ReplacementPrefixes::for_target_os(target_os);
    rewrite_entry_path_with_prefixes(
        entry_path,
        target_os,
        &data_prefix,
        &prefixes,
        rewritten_scripts,
    )
}

/// Rewrites wheel `RECORD` CSV content from `reader` to `writer` with `\n` line endings.
///
/// # Errors
///
/// Returns an error if the input cannot be parsed as CSV or the output cannot be written.
pub fn rewrite_record_stream<R: Read, W: Write>(
    reader: R,
    writer: W,
    target_os: TargetOs,
    data_dir_basename: &str,
    rewritten_scripts: &HashSet<String>,
) -> Result<()> {
    let data_prefix = format!("{data_dir_basename}/");
    let prefixes = ReplacementPrefixes::for_target_os(target_os);

    let mut csv_reader = csv::ReaderBuilder::new()
        .has_headers(false)
        .flexible(true)
        .from_reader(reader);
    let mut csv_writer = csv::WriterBuilder::new()
        .has_headers(false)
        .flexible(true)
        .terminator(csv::Terminator::Any(b'\n'))
        .from_writer(writer);

    let mut record = csv::StringRecord::new();
    while csv_reader
        .read_record(&mut record)
        .context("reading RECORD entry")?
    {
        let rewritten_path = rewrite_entry_path_with_prefixes(
            &record[0],
            target_os,
            &data_prefix,
            &prefixes,
            rewritten_scripts,
        );
        csv_writer
            .write_field(&rewritten_path)
            .with_context(|| format!("writing RECORD entry {rewritten_path}"))?;
        csv_writer
            .write_record(record.iter().skip(1))
            .with_context(|| format!("writing RECORD entry {rewritten_path}"))?;
    }

    csv_writer.flush().context("flushing RECORD output")
}

/// Rewrites an in-memory `RECORD` string and returns the rewritten UTF-8 string.
///
/// # Errors
///
/// Returns an error if the input cannot be parsed as CSV.
pub fn rewrite_record_str(
    input: &str,
    target_os: TargetOs,
    data_dir_basename: &str,
    rewritten_scripts: &HashSet<String>,
) -> Result<String> {
    let mut output = Vec::with_capacity(input.len());
    rewrite_record_stream(
        input.as_bytes(),
        &mut output,
        target_os,
        data_dir_basename,
        rewritten_scripts,
    )?;
    String::from_utf8(output).context("rewritten RECORD is not valid UTF-8")
}

/// Rewrites the wheel `RECORD` file at `in_path` to `out_path`.
///
/// # Errors
///
/// Returns an error if `in_path` cannot be read, `out_path` cannot be created, or the
/// `RECORD` content cannot be parsed.
pub fn rewrite_record_files(
    in_path: &Path,
    out_path: &Path,
    target_os: TargetOs,
    data_dir_basename: &str,
    rewritten_scripts: &HashSet<String>,
) -> Result<()> {
    let in_file = File::open(in_path).with_context(|| format!("opening {}", in_path.display()))?;
    let out_file =
        File::create(out_path).with_context(|| format!("creating {}", out_path.display()))?;

    rewrite_record_stream(
        in_file,
        out_file,
        target_os,
        data_dir_basename,
        rewritten_scripts,
    )
    .with_context(|| format!("rewriting {} to {}", in_path.display(), out_path.display()))
}

/// Rewrites a wheel `RECORD` file using the provided [`Options`].
///
/// # Errors
///
/// See [`rewrite_record_files`].
pub fn rewrite_record(options: &Options) -> Result<()> {
    rewrite_record_files(
        &options.in_path,
        &options.out_path,
        options.target_os,
        &options.data_dir_basename,
        &options.rewritten_scripts,
    )
}

fn into_utf8(raw: OsString, what: &str) -> Result<String> {
    raw.into_string()
        .map_err(|raw| anyhow!("invalid UTF-8 in {what}: {raw:?}"))
}

/// Parses command-line arguments (excluding `argv[0]` and subcommand name) into [`ParsedArgs`].
///
/// Expected positional arguments:
/// `<in_path> <out_path> <target_os> <data_dir_basename> [rewritten_scripts...]`
///
/// # Errors
///
/// Returns an error for unknown flags, fewer than four positional arguments, an unsupported
/// `target_os`, or non-UTF-8 `target_os`, `data_dir_basename`, or script names.
pub fn parse_args<I, T>(args: I) -> Result<ParsedArgs>
where
    I: IntoIterator<Item = T>,
    T: Into<OsString>,
{
    let mut positional: Vec<OsString> = Vec::new();

    let mut parser = lexopt::Parser::from_args(args);
    while let Some(arg) = parser.next()? {
        match arg {
            Short(flags::HELP_SHORT) | Long(flags::HELP) => return Ok(ParsedArgs::Help),
            Value(val) => positional.push(val),
            _ => bail!("{}", arg.unexpected()),
        }
    }

    if positional.len() < 4 {
        bail!(
            "expected at least 4 positional arguments (<in_path> <out_path> <target_os> <data_dir_basename>), got {}",
            positional.len()
        );
    }
    let in_path = PathBuf::from(positional.remove(0));
    let out_path = PathBuf::from(positional.remove(0));
    let target_os_str = into_utf8(positional.remove(0), "target_os")?;
    let target_os = if target_os_str == "unix" {
        TargetOs::Unix
    } else if target_os_str == "windows" {
        TargetOs::Windows
    } else {
        bail!("unsupported target_os '{target_os_str}'; expected 'unix' or 'windows'");
    };
    let data_dir_basename = into_utf8(positional.remove(0), "data_dir_basename")?;
    let mut rewritten_scripts = HashSet::with_capacity(positional.len());
    for raw in positional {
        rewritten_scripts.insert(into_utf8(raw, "rewritten script name")?);
    }

    Ok(ParsedArgs::Options(Options {
        in_path,
        out_path,
        target_os,
        data_dir_basename,
        rewritten_scripts,
    }))
}

/// Parses CLI arguments (excluding `argv[0]` and subcommand name), rewrites the wheel `RECORD`
/// file, and returns the process exit code.
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
            eprintln!("wheel_record_rewriter: error: {err:#}");
            return ExitCode::FAILURE;
        }
    };
    if let Err(err) = rewrite_record(&options) {
        eprintln!("wheel_record_rewriter: error: {err:#}");
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}

/// Result of parsing command-line arguments.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ParsedArgs {
    /// `--help` was requested.
    Help,
    /// Parsed command-line options.
    Options(Options),
}

/// Parsed command-line options for `wheel_record_rewriter`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Options {
    /// Path to the original `RECORD` file, relative to the current working directory or absolute.
    pub in_path: PathBuf,
    /// Path to write the rewritten `RECORD` file, relative to the current working directory or
    /// absolute.
    pub out_path: PathBuf,
    /// Target installation layout.
    pub target_os: TargetOs,
    /// Basename of the wheel's `.data` directory (e.g. `foo-1.0.data`).
    pub data_dir_basename: String,
    /// Script paths relative to `<data_dir_basename>/scripts/` that had shebang rewriting applied.
    pub rewritten_scripts: HashSet<String>,
}

/// Target operating system layout for PEP 376 wheel `RECORD` path rewriting.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TargetOs {
    Unix,
    Windows,
}

/// Replacement prefixes corresponding to PEP 376 installation paths.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct ReplacementPrefixes {
    data_repl: &'static str,
    headers_repl: &'static str,
    platlib_repl: &'static str,
    purelib_repl: &'static str,
    scripts_repl: &'static str,
}

impl ReplacementPrefixes {
    const fn for_target_os(target_os: TargetOs) -> Self {
        match target_os {
            TargetOs::Windows => Self {
                data_repl: "../../",
                headers_repl: "../../Include/",
                platlib_repl: "",
                purelib_repl: "",
                scripts_repl: "../../Scripts/",
            },
            TargetOs::Unix => Self {
                data_repl: "../../../",
                headers_repl: "../../../include/",
                platlib_repl: "",
                purelib_repl: "",
                scripts_repl: "../../../bin/",
            },
        }
    }
}

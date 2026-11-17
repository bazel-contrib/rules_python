//! Library for extracting files from a Python wheel (`.whl`) archive matching a regex pattern.
//!
//! Reads the `.dist-info/RECORD` file from `<wheel>`, filters column 0 file paths using
//! start-anchored regex matching (`re.match` semantics), and extracts matching files into
//! `<out_dir>`.

// Errors must be returned, not panicked; see the `rust-lint` config in .bazelrc.
#![deny(clippy::expect_used, clippy::unwrap_used)]

use std::ffi::OsString;
use std::fs::{self, File};
use std::io::{self, BufReader, Read};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use anyhow::{Context, Result, bail};
use lexopt::prelude::*;
use regex::Regex;
use zip::ZipArchive;

mod flags {
    // keep-sorted start
    pub const HELP: &str = "help";
    pub const HELP_SHORT: char = 'h';
    // keep-sorted end
}

/// Usage text for `--help`. `lexopt` does not generate help, so this is maintained by hand.
const USAGE: &str = "\
Usage: extract_wheel_files <wheel> <out_dir> [regex_pattern]

Extract the files listed in a wheel's RECORD that match a regex pattern.

Arguments:
  <wheel>           Path to the wheel to extract from
  <out_dir>         Directory to extract the matching files into
  [regex_pattern]   Start-anchored regex the RECORD paths must match (default: match all)

Options:
  -h, --help        Print this help";

/// Compiles a start-anchored regular expression (`Python re.match` semantics).
///
/// # Errors
///
/// Returns an error if `regex_pattern` is not valid regular expression syntax.
pub fn compile_pattern(regex_pattern: &str) -> Result<Regex> {
    let anchored_pattern = format!(r"\A(?:{regex_pattern})");
    Regex::new(&anchored_pattern).with_context(|| format!("invalid regex '{regex_pattern}'"))
}

/// Parses CSV `RECORD` bytes and returns the list of file paths (column 0), relative to the
/// wheel root.
///
/// # Errors
///
/// Returns an error if `record_bytes` contains malformed CSV records or invalid UTF-8.
pub fn parse_record(record_bytes: &[u8]) -> Result<Vec<String>> {
    let mut reader = csv::ReaderBuilder::new()
        .has_headers(false)
        .flexible(true)
        .from_reader(record_bytes);
    let mut paths = Vec::new();
    for result in reader.records() {
        let record = result.context("parsing RECORD CSV")?;
        if let Some(first) = record.get(0) {
            paths.push(first.to_owned());
        }
    }
    Ok(paths)
}

/// Reads the `.dist-info/RECORD` file from `whl_path` and returns the list of file paths
/// (column 0), relative to the wheel root.
///
/// # Errors
///
/// Returns an error if `whl_path` cannot be opened as a valid ZIP archive, does not contain
/// exactly one `.dist-info/RECORD` entry, or the `RECORD` entry cannot be read and parsed.
pub fn get_record(whl_path: &Path) -> Result<Vec<String>> {
    let mut archive = open_wheel_archive(whl_path)?;
    // zip 9 returns `Result<Cow<str>>` per entry name; a bad name means the
    // archive is malformed, so surface it rather than skipping the entry.
    let mut record_names: Vec<String> = Vec::new();
    for name in archive.file_names() {
        let name = name.with_context(|| format!("{}: invalid entry name", whl_path.display()))?;
        if name.ends_with(".dist-info/RECORD") {
            record_names.push(name.into_owned());
        }
    }

    let [record_name] = record_names.as_slice() else {
        bail!(
            "{} doesn't contain exactly one .dist-info/RECORD",
            whl_path.display()
        );
    };

    let mut record_bytes = Vec::new();
    archive
        .by_name(record_name)
        .and_then(|mut entry| Ok(entry.read_to_end(&mut record_bytes)?))
        .with_context(|| format!("reading {record_name} from {}", whl_path.display()))?;

    parse_record(&record_bytes)
}

/// Filters `whl_record` entries by a pre-compiled `regex`, returning matching paths relative to
/// the wheel root.
pub fn get_files<I, S>(whl_record: I, regex: &Regex) -> Vec<String>
where
    I: IntoIterator<Item = S>,
    S: AsRef<str>,
{
    whl_record
        .into_iter()
        .filter(|entry| regex.is_match(entry.as_ref()))
        .map(|entry| entry.as_ref().to_owned())
        .collect()
}

/// Extracts `files` from `whl_path` into `outdir`.
///
/// # Errors
///
/// Returns an error if `outdir` cannot be created, `whl_path` cannot be opened, or any entry in
/// `files` is missing from the archive or cannot be written to disk.
pub fn extract_files<I, S>(whl_path: &Path, files: I, outdir: &Path) -> Result<()>
where
    I: IntoIterator<Item = S>,
    S: AsRef<str>,
{
    fs::create_dir_all(outdir).with_context(|| format!("creating {}", outdir.display()))?;

    let mut archive = open_wheel_archive(whl_path)?;
    for file in files {
        let entry_name = file.as_ref();
        let mut entry = archive
            .by_name(entry_name)
            .with_context(|| format!("opening '{entry_name}' in {}", whl_path.display()))?;

        let dest_path = sanitize_extract_path(outdir, entry_name);
        if entry.is_dir() {
            fs::create_dir_all(&dest_path)
                .with_context(|| format!("creating {}", dest_path.display()))?;
            continue;
        }

        if let Some(parent) = dest_path.parent() {
            fs::create_dir_all(parent).with_context(|| format!("creating {}", parent.display()))?;
        }

        let mut out_file = File::create(&dest_path)
            .with_context(|| format!("creating {}", dest_path.display()))?;
        io::copy(&mut entry, &mut out_file)
            .with_context(|| format!("extracting '{entry_name}' to {}", dest_path.display(),))?;
    }

    Ok(())
}

fn open_wheel_archive(whl_path: &Path) -> Result<ZipArchive<BufReader<File>>> {
    let file = File::open(whl_path).with_context(|| format!("opening {}", whl_path.display()))?;
    ZipArchive::new(BufReader::new(file))
        .with_context(|| format!("{} is not a valid zip file", whl_path.display()))
}

/// Mirrors `zipfile.ZipFile._extract_member`: drops empty, `.`, and `..` path components so an
/// entry cannot escape `outdir`.
fn sanitize_extract_path(outdir: &Path, entry_name: &str) -> PathBuf {
    let mut dest = outdir.to_path_buf();
    dest.extend(
        entry_name
            .split(['/', '\\'])
            .filter(|part| !part.is_empty() && *part != "." && *part != ".."),
    );
    dest
}

/// Executes the full `extract_wheel_files` workflow for the given options.
///
/// # Errors
///
/// Returns an error if the wheel or its `.dist-info/RECORD` cannot be read or matching entries
/// cannot be extracted into `options.outdir`.
pub fn run(options: &Options) -> Result<()> {
    let record = get_record(&options.whl_path)?;
    let files = get_files(&record, &options.regex);
    extract_files(&options.whl_path, &files, &options.outdir)
}

/// Parses command-line arguments (excluding `argv[0]` and subcommand name) into [`ParsedArgs`].
///
/// # Errors
///
/// Returns an error if an unknown flag is passed, the positional argument count is not 2 or 3,
/// or the regex pattern is invalid UTF-8 or invalid regular expression syntax.
pub fn parse_args<I, T>(args: I) -> Result<ParsedArgs>
where
    I: IntoIterator<Item = T>,
    T: Into<OsString>,
{
    let mut positional: Vec<OsString> = Vec::new();

    let mut parser = lexopt::Parser::from_args(args.into_iter().map(Into::into));
    while let Some(arg) = parser.next()? {
        match arg {
            Short(flags::HELP_SHORT) | Long(flags::HELP) => return Ok(ParsedArgs::Help),
            Value(val) => positional.push(val),
            _ => bail!("{}", arg.unexpected()),
        }
    }

    if positional.len() != 2 && positional.len() != 3 {
        bail!(
            "expected 2 or 3 positional arguments (<wheel> <out_dir> [regex_pattern]), got {}",
            positional.len()
        );
    }

    // The length check above guarantees the first two positionals exist.
    let whl_path = PathBuf::from(positional.remove(0));
    let outdir = PathBuf::from(positional.remove(0));
    let regex_pattern = if let Some(raw) = positional.pop() {
        raw.into_string()
            .ok()
            .context("regex pattern is not valid UTF-8")?
    } else {
        String::new()
    };
    let regex = compile_pattern(&regex_pattern)?;

    Ok(ParsedArgs::Options(Options {
        whl_path,
        outdir,
        regex,
    }))
}

/// Parses CLI arguments (excluding `argv[0]` and subcommand name), extracts matching wheel files,
/// and returns the process exit code.
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
            eprintln!("extract_wheel_files: error: {err:#}");
            return ExitCode::FAILURE;
        }
    };
    if let Err(err) = run(&options) {
        eprintln!("extract_wheel_files: error: {err:#}");
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}

/// Result of parsing command-line arguments.
#[derive(Debug, Clone)]
pub enum ParsedArgs {
    /// `--help` was requested.
    Help,
    /// Parsed command-line options.
    Options(Options),
}

/// Parsed CLI options for `extract_wheel_files`.
#[derive(Debug, Clone)]
pub struct Options {
    /// Path to the input `.whl` file, relative to the current working directory or absolute.
    pub whl_path: PathBuf,
    /// Directory to extract matching files into, relative to the current working directory or
    /// absolute.
    pub outdir: PathBuf,
    /// Start-anchored pattern RECORD paths must match.
    pub regex: Regex,
}

//! Library for creating the `__main__.py` for a zipapp by populating a template.
//!
//! This library also calculates a SHA-256 hash of the application files from a manifest to include
//! in the template, which allows making the extraction directory unique to the content of the
//! zipapp.

// Errors must be returned, not panicked; see the `rust-lint` config in .bazelrc.
#![deny(clippy::expect_used, clippy::unwrap_used)]

use std::collections::HashMap;
use std::ffi::OsString;
use std::fs::{self, File};
use std::io;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use anyhow::{Context, Result, bail};
use lexopt::prelude::*;
use sha2::{Digest, Sha256};
use zip_manifest::{SymlinkMode, parse_manifest_line};

/// Template placeholder replaced with the computed SHA-256 hex digest of the application inputs.
pub const APP_HASH_PLACEHOLDER: &str = "%APP_HASH%";

mod flags {
    // keep-sorted start
    pub const HASH_FILES_MANIFEST: &str = "hash_files_manifest";
    pub const HELP: &str = "help";
    pub const HELP_SHORT: char = 'h';
    pub const OUTPUT: &str = "output";
    pub const SUBSTITUTION: &str = "substitution";
    pub const TEMPLATE: &str = "template";
    // keep-sorted end
}

/// Usage text for `--help`. `lexopt` does not generate help, so this is maintained by hand.
const USAGE: &str = "\
Usage: zip_main_maker [OPTIONS] --template <PATH> --output <PATH> --hash_files_manifest <PATH>

Create the __main__.py for a zipapp from a template and input manifest.

Options:
  --template <PATH>              Path to the __main__.py template file
  --output <PATH>                Path to the generated __main__.py output file
  --substitution <KEY=VALUE>     Template substitution (may be passed multiple times)
  --hash_files_manifest <PATH>   File containing lines in rf-XXX formats (rf-empty, rf-file, rf-symlink, etc.)
  @<FLAGFILE>                    Read newline-delimited arguments from <FLAGFILE>
  -h, --help                     Print this help";

/// Computes the SHA-256 lowercase hex digest of the application inputs listed in `manifest_path`.
///
/// Manifest lines are parsed via [`parse_manifest_line`] and sorted lexicographically for
/// determinism; for each line, the text after the leading `<type>|` prefix is hashed to capture
/// the runfiles structure, followed by either the symlink target UTF-8 bytes or the file's raw
/// content bytes.
pub fn compute_inputs_hash(manifest_path: &Path) -> Result<String> {
    let content = fs::read_to_string(manifest_path)
        .with_context(|| format!("reading manifest {}", manifest_path.display()))?;
    let mut manifest_lines: Vec<&str> = content.lines().collect();

    // Sort lines for determinism. Hash the paths (to capture structure) and the content.
    manifest_lines.sort_unstable();

    let mut hasher = Sha256::new();

    for line in manifest_lines {
        let parsed = parse_manifest_line(line)
            .with_context(|| format!("in manifest {}", manifest_path.display()))?;
        hasher.update(parsed.rest.as_bytes());

        // For `rf-empty` and `symlink`, the paths (and symlink target) are captured by hashing
        // `parsed.rest` above.
        let Some((symlink_mode, path)) = parsed.entry.content_source() else {
            continue;
        };

        let is_symlink = match symlink_mode {
            SymlinkMode::Regular => false,
            SymlinkMode::Symlink => true,
            SymlinkMode::Infer => !path.exists(),
        };

        if is_symlink {
            let link_target = fs::read_link(path)
                .with_context(|| format!("reading symlink {}", path.display()))?;
            hasher.update(link_target.to_string_lossy().as_bytes());
        } else {
            let mut file =
                File::open(path).with_context(|| format!("opening {}", path.display()))?;
            io::copy(&mut file, &mut hasher)
                .with_context(|| format!("hashing {}", path.display()))?;
        }
    }

    Ok(format!("{:x}", hasher.finalize()))
}

/// Reads `template_path`, applies `substitutions`, and writes the result to `output_path`.
pub fn expand_template(
    template_path: &Path,
    output_path: &Path,
    substitutions: &HashMap<&str, &str>,
) -> Result<()> {
    let mut content = fs::read_to_string(template_path)
        .with_context(|| format!("reading template {}", template_path.display()))?;

    for (&key, &val) in substitutions {
        content = content.replace(key, val);
    }

    if let Some(parent) = output_path.parent()
        && !parent.as_os_str().is_empty()
    {
        fs::create_dir_all(parent)
            .with_context(|| format!("creating directory {}", parent.display()))?;
    }

    fs::write(output_path, content)
        .with_context(|| format!("writing output {}", output_path.display()))
}

/// Generates `__main__.py` according to `options`.
pub fn generate_zip_main(options: &Options) -> Result<()> {
    let app_hash = compute_inputs_hash(&options.hash_files_manifest)?;
    let mut substitutions = HashMap::from([(APP_HASH_PLACEHOLDER, app_hash.as_str())]);
    for (key, val) in &options.substitutions {
        substitutions.insert(key, val);
    }
    expand_template(&options.template, &options.output, &substitutions)
}

fn parse_substitution(raw: &str) -> std::result::Result<(String, String), String> {
    let (key, val) = raw.split_once('=').ok_or_else(|| {
        format!(
            "invalid --{} value (expected KEY=VALUE): {raw}",
            flags::SUBSTITUTION
        )
    })?;
    Ok((key.to_string(), val.to_string()))
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

    let mut template: Option<PathBuf> = None;
    let mut output: Option<PathBuf> = None;
    let mut substitutions: HashMap<String, String> = HashMap::new();
    let mut hash_files_manifest: Option<PathBuf> = None;

    let mut parser = lexopt::Parser::from_args(expanded);
    while let Some(arg) = parser.next()? {
        match arg {
            Short(flags::HELP_SHORT) | Long(flags::HELP) => return Ok(Cli::Help),
            Long(flags::TEMPLATE) => {
                template = Some(PathBuf::from(parser.value()?));
            }
            Long(flags::OUTPUT) => {
                output = Some(PathBuf::from(parser.value()?));
            }
            Long(flags::SUBSTITUTION) => {
                let (key, val) = parser.value()?.parse_with(parse_substitution)?;
                substitutions.insert(key, val);
            }
            Long(flags::HASH_FILES_MANIFEST) => {
                hash_files_manifest = Some(PathBuf::from(parser.value()?));
            }
            _ => bail!("{}", arg.unexpected()),
        }
    }

    let template =
        template.with_context(|| format!("missing required argument: --{}", flags::TEMPLATE))?;
    let output =
        output.with_context(|| format!("missing required argument: --{}", flags::OUTPUT))?;
    let hash_files_manifest = hash_files_manifest.with_context(|| {
        format!(
            "missing required argument: --{}",
            flags::HASH_FILES_MANIFEST
        )
    })?;

    Ok(Cli::Run(Options {
        template,
        output,
        substitutions,
        hash_files_manifest,
    }))
}

/// Parses CLI arguments (excluding `argv[0]` and subcommand name), generates `__main__.py`, and
/// returns the process exit code.
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
            eprintln!("zip_main_maker: error: {err:#}");
            return ExitCode::FAILURE;
        }
    };
    if let Err(err) = generate_zip_main(&options) {
        eprintln!("zip_main_maker: error: {err:#}");
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}

/// Result of parsing the command line.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Cli {
    /// `--help` was requested.
    Help,
    /// Generate `__main__.py` with the given options.
    Run(Options),
}

/// Parsed command-line options for `zip_main_maker`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Options {
    /// Path to the `__main__.py` template file, relative to the current working directory or
    /// absolute.
    pub template: PathBuf,
    /// Path to the generated `__main__.py` output file, relative to the current working directory
    /// or absolute.
    pub output: PathBuf,
    /// `(key, value)` template substitutions passed via `--substitution`.
    pub substitutions: HashMap<String, String>,
    /// Path to the input manifest file listing application files to hash, relative to the current
    /// working directory or absolute.
    pub hash_files_manifest: PathBuf,
}

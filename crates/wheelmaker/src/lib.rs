//! Library for building deterministic Python `.whl` archives (PEP 427).
//!
//! Mirrors `tools/wheelmaker.py` with two intentional differences stemming from its pure-Rust
//! dependencies:
//! * Compressed `.whl` archives use `flate2`'s pure-Rust `zlib-rs` backend rather than C `zlib`,
//!   so compressed byte streams (and outer `.whl` file digests) differ while archive entries and
//!   `RECORD` SHA-256 digests are identical.
//! * `Requires-Dist` lines parsed through `pep508_rs` normalize distribution names (PEP 503),
//!   extra names (PEP 685), and environment markers (algebraic PEP 508 simplification).

// Errors must be returned, not panicked; see the `rust-lint` config in .bazelrc.
#![deny(clippy::expect_used, clippy::unwrap_used)]

use std::collections::HashMap;
use std::ffi::OsString;
use std::fs::{self, File};
use std::io::{BufWriter, Read, Seek, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::str::FromStr;

use anyhow::{Context, Result, bail};
use base64::Engine as _;
use lexopt::prelude::*;
use regex::Regex;
use sha2::{Digest, Sha256};
use zip::write::SimpleFileOptions;
use zip::{CompressionMethod, DateTime, System, ZIP64_BYTES_THR, ZipWriter};

/// Read/write buffer size when streaming files into the `.whl` archive and SHA-256 hasher.
///
/// 256 KiB matches the other `shrubbery` tools (`zipper`, `exe_zip_maker`, `zip_main_maker`). It
/// is large enough to coalesce small wheel entries into few `write` syscalls and amortize `read`
/// syscalls on large files, while staying small enough to fit in L2 cache where bigger buffers
/// stop paying off.
const BLOCK_SIZE: usize = 256 * 1024;

/// Fixed timestamp for all entries so output is deterministic. This is the earliest MS-DOS
/// timestamp a zip can represent (1980-01-01 00:00:00) and matches `_ZIP_EPOCH` in
/// `tools/wheelmaker.py`.
const FIXED_TIMESTAMP: DateTime = DateTime::DEFAULT;

/// Permissions `-rwxrwxrwx` with regular file bit (`S_IFREG | 0o777`).
///
/// Both `pip` and `installer` expect the regular file bit to be set in order for the executable
/// bit to be preserved after extraction:
/// * <https://github.com/pypa/pip/blob/23.3.2/src/pip/_internal/utils/unpacking.py#L96-L100>
/// * <https://github.com/pypa/installer/blob/0.7.0/src/installer/sources.py#L310-L313>
pub const REGULAR_FILE_UNIX_MODE: u32 = 0o100777;

mod flags {
    // keep-sorted start
    pub const ABI: &str = "abi";
    pub const BUILD_TAG: &str = "build_tag";
    pub const DATA_FILES: &str = "data_files";
    pub const DESCRIPTION_FILE: &str = "description_file";
    pub const ENTRY_POINTS_FILE: &str = "entry_points_file";
    pub const EXTRA_DISTINFO_FILE: &str = "extra_distinfo_file";
    pub const HELP: &str = "help";
    pub const HELP_SHORT: char = 'h';
    pub const INPUT_FILE: &str = "input_file";
    pub const INPUT_FILE_LIST: &str = "input_file_list";
    pub const METADATA_FILE: &str = "metadata_file";
    pub const NAME: &str = "name";
    pub const NAME_FILE: &str = "name_file";
    pub const NO_COMPRESS: &str = "no_compress";
    pub const OUT: &str = "out";
    pub const PATH_PREFIX: &str = "path_prefix";
    pub const PLATFORM: &str = "platform";
    pub const PYTHON_TAG: &str = "python_tag";
    pub const STABLE_STATUS_FILE: &str = "stable_status_file";
    pub const STRIP_PATH_PREFIX: &str = "strip_path_prefix";
    pub const VERSION: &str = "version";
    pub const VOLATILE_STATUS_FILE: &str = "volatile_status_file";
    // keep-sorted end
}

/// Usage text for `--help`. `lexopt` does not generate help, so this is maintained by hand.
const USAGE: &str = "\
Usage: wheelmaker [OPTIONS] --name <NAME> --version <VERSION> --metadata_file <PATH>

Build a deterministic Python wheel (.whl) archive.

Wheel name, version, and platform:
  --name <NAME>                          Name of the distribution
  --version <VERSION>                    Version of the distribution
  --build_tag <TAG>                      Optional build tag for the distribution
  --python_tag <TAG>                     Python version tag, e.g. 'py2' or 'py3' (default: py3)
  --abi <ABI>                            Python ABI tag (default: none)
  --platform <PLATFORM>                  Target platform tag (default: any)

Output and path rewriting:
  --out <PATH>                           Override output .whl file path
  --no_compress                          Disable compression of the final archive
  --name_file <PATH>                     File where the canonical wheel filename is written
  --strip_path_prefix <PREFIX>           Path prefix stripped from input package paths
                                         (repeatable, evaluated in order)
  --path_prefix <PREFIX>                 Path prefix prepended to input package paths after
                                         stripping

Wheel metadata and contents:
  --metadata_file <PATH>                 Contents of METADATA before appending description
  --description_file <PATH>              Path to the package description file
  --entry_points_file <PATH>             Path to an entry_points.txt file
  --input_file <PACKAGE_PATH;REAL_PATH>  File or directory to include in the wheel (repeatable)
  --input_file_list <PATH>               File listing 'package_path;real_path' pairs, one per
                                         line (repeatable)
  --extra_distinfo_file <NAME;REAL_PATH> Extra file to include in .dist-info/ (repeatable)
  --data_files <NAME;REAL_PATH>          Data file to include in .data/ (repeatable)

Workspace status stamping:
  --volatile_status_file <PATH>          Volatile workspace status file for stamping
  --stable_status_file <PATH>            Stable workspace status file for stamping
  @<FLAGFILE>                            Read newline-delimited arguments from <FLAGFILE>
  -h, --help                             Print this help";

/// Normalizes a package name according to the Python Packaging User Guide.
///
/// See <https://packaging.python.org/en/latest/specifications/name-normalization/>.
pub fn normalize_package_name(name: &str) -> Result<String> {
    let re = Regex::new(r"[-_.]+")?;
    Ok(re.replace_all(name, "-").to_lowercase())
}

/// Escapes the distribution name component of a wheel filename.
///
/// See <https://packaging.python.org/en/latest/specifications/binary-distribution-format/#escaping-and-unicode>.
pub fn escape_filename_distribution_name(name: &str) -> Result<String> {
    Ok(normalize_package_name(name)?.replace('-', "_"))
}

/// Normalizes `version` according to PEP 440, with fallback for `{PLACEHOLDER}` stamps.
///
/// If there is a placeholder in braces, such as `{BUILD_TIMESTAMP}`, replaces it with `0`. Such
/// placeholders can be used with stamping, in which case they would have been resolved already;
/// if they have not, this is an unstamped build that still needs a valid PEP 440 version. When
/// replacements are made, the original version string (sanitized to dot-separated alphanumerics)
/// is appended as a local version segment so the placeholder remains visible.
///
/// If that still does not produce a valid PEP 440 version, falls back to `0+<sanitized>`.
pub fn normalize_pep440(version: &str) -> Result<String> {
    if let Ok(ver) = pep440_rs::Version::from_str(version.trim()) {
        return Ok(ver.to_string());
    }

    let local_sanitize_re = Regex::new(r"[^a-z0-9]+")?;
    let brace_placeholder_re = Regex::new(r"\{\w+\}")?;

    let lowered = version.to_lowercase();
    let sanitized = local_sanitize_re
        .replace_all(&lowered, ".")
        .trim_matches('.')
        .to_string();
    let substituted = brace_placeholder_re.replace_all(version, "0");
    let delimiter = if substituted.contains('+') { "." } else { "+" };
    let candidate = format!("{substituted}{delimiter}{sanitized}");
    if let Ok(ver) = pep440_rs::Version::from_str(&candidate) {
        return Ok(ver.to_string());
    }

    let fallback = format!("0+{sanitized}");
    pep440_rs::Version::from_str(&fallback)
        .map(|ver| ver.to_string())
        .with_context(|| format!("invalid PEP 440 version: {version:?}"))
}

/// Returns the archive-root-relative path (using `/` separators) for `name`.
///
/// Prefixes in `strip_path_prefixes` are checked in order and only the first match is stripped,
/// after which `add_path_prefix` is prepended. Paths already starting with `distribution_prefix`
/// (such as `.dist-info/` and `.data/` entries) are returned without prefix rewriting.
pub fn arcname_from(
    name: &str,
    distribution_prefix: &str,
    strip_path_prefixes: &[String],
    add_path_prefix: &str,
) -> String {
    // Always use Unix path separators inside zip archives.
    let normalized_arcname = name.replace('\\', "/");
    // Don't manipulate filenames in the .dist-info or .data directories.
    if !distribution_prefix.is_empty() && normalized_arcname.starts_with(distribution_prefix) {
        return normalized_arcname;
    }
    let normalized_prefix = add_path_prefix.replace('\\', "/");
    for prefix in strip_path_prefixes {
        if let Some(stripped) = normalized_arcname.strip_prefix(prefix.as_str()) {
            return format!("{normalized_prefix}{stripped}");
        }
    }
    format!("{normalized_prefix}{normalized_arcname}")
}

/// Formats a raw SHA-256 digest as `sha256=<urlsafe_b64_nopad>` per PEP 376 (`RECORD`).
///
/// See <https://peps.python.org/pep-0376/#record> (`urlsafe_b64encode(digest)` with trailing `=`
/// removed).
pub fn serialize_digest(sha256_bytes: &[u8]) -> String {
    format!(
        "sha256={}",
        base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(sha256_bytes)
    )
}

fn format_requirement(req: &pep508_rs::Requirement<pep508_rs::VerbatimUrl>) -> String {
    let mut out = format!("Requires-Dist: {}", req.name);
    if !req.extras.is_empty() {
        let mut extras: Vec<String> = req.extras.iter().map(ToString::to_string).collect();
        extras.sort_unstable();
        extras.dedup();
        out.push('[');
        out.push_str(&extras.join(","));
        out.push(']');
    }
    let is_url = match &req.version_or_url {
        Some(pep508_rs::VersionOrUrl::VersionSpecifier(specs)) => {
            let mut spec_strs: Vec<String> = specs.iter().map(ToString::to_string).collect();
            spec_strs.sort_unstable();
            spec_strs.dedup();
            out.push_str(&spec_strs.join(","));
            false
        }
        Some(pep508_rs::VersionOrUrl::Url(url)) => {
            out.push_str(" @ ");
            if let Some(given) = url.given() {
                out.push_str(given);
            } else {
                out.push_str(&url.to_string());
            }
            true
        }
        None => false,
    };
    if let Some(marker) = req.marker.contents() {
        // PEP 508 requires whitespace before `;` after a URL so `;` is not parsed as part of the
        // URI itself.
        let sep = if is_url { " ; " } else { "; " };
        out.push_str(sep);
        out.push_str(&marker.to_string());
    }
    out
}

/// Formats a PEP 508 requirement string and optional extra marker expression into a `Requires-Dist`
/// metadata line.
///
/// Uses `pep508_rs`, which normalizes package names (PEP 503), extra names (PEP 685), and
/// environment markers.
///
/// # Errors
///
/// Returns an error if `reqs_text` is not a valid PEP 508 requirement or `extra` is not a valid
/// PEP 508 marker expression.
pub fn get_new_requirement_line(reqs_text: &str, extra: &str) -> Result<String> {
    let mut req = pep508_rs::Requirement::<pep508_rs::VerbatimUrl>::from_str(reqs_text.trim())
        .with_context(|| format!("parsing requirement {reqs_text:?}"))?;
    let extra_trimmed = extra.trim();
    if !extra_trimmed.is_empty() {
        let extra_tree = pep508_rs::MarkerTree::from_str(extra_trimmed)
            .with_context(|| format!("parsing extra marker {extra_trimmed:?}"))?;
        req.marker.and(extra_tree);
    }
    Ok(format_requirement(&req))
}

/// Resolves `{KEY}` workspace status placeholders in `argument` using `KEY VALUE` lines read from
/// Bazel status files.
pub fn resolve_stamp_with_lines(argument: &str, status_lines: &[String]) -> String {
    let mut resolved = argument.to_string();
    for line in status_lines {
        if line.is_empty() {
            continue;
        }
        let (key, value) = line.split_once(' ').unwrap_or((line.as_str(), ""));
        let stamp = format!("{{{key}}}");
        resolved = resolved.replace(&stamp, value);
    }
    resolved
}

fn read_text(path: &Path) -> Result<String> {
    fs::read_to_string(path).with_context(|| format!("reading {}", path.display()))
}

/// Expands `Requires-Dist:` lines in `metadata` (both inline requirements with `;` markers and
/// `@file` requirement-file directives).
///
/// # Errors
///
/// Returns an error if a referenced `@file` requirements file cannot be read, or if an inline
/// requirement, extra marker, or requirements-file entry is not valid PEP 508 syntax.
pub fn expand_metadata_requires(metadata: &str) -> Result<String> {
    let mut out = String::with_capacity(metadata.len());

    for meta_line in metadata.lines() {
        let Some(after_prefix) = meta_line.strip_prefix("Requires-Dist: ") else {
            out.push_str(meta_line);
            out.push('\n');
            continue;
        };

        let Some(after_at) = after_prefix.strip_prefix('@') else {
            // Normal inline requirement: only re-format when a `;` marker/extra is present,
            // matching `tools/wheelmaker.py`.
            let Some((package, extra)) = after_prefix.rsplit_once(';') else {
                out.push_str(meta_line);
                out.push('\n');
                continue;
            };
            let formatted = get_new_requirement_line(package, extra.trim())
                .with_context(|| format!("in metadata line {meta_line:?}"))?;
            out.push_str(&formatted);
            out.push('\n');
            continue;
        };

        // Requirement directive referring to an external requirements file (`@path[; extra]`).
        let (file_part, extra) = match after_at.split_once(';') {
            Some((f, e)) => (f, e.trim()),
            None => (after_at, ""),
        };
        let req_file_text = read_text(Path::new(file_part))?;
        // If the referenced requirements file has no requirements, nothing is pushed and the
        // directive line is dropped entirely.
        for reqs_text in req_file_text
            .lines()
            .map(str::trim)
            .filter(|line| !(line.is_empty() || line.starts_with(['#', '-'])))
            .map(|line| {
                // Strip inline comments.
                line.split_once('#')
                    .map_or(line, |(before_comment, _)| before_comment)
            })
        {
            let formatted = get_new_requirement_line(reqs_text, extra)
                .with_context(|| format!("in requirements file {file_part}"))?;
            out.push_str(&formatted);
            out.push('\n');
        }
    }

    Ok(out)
}

fn create_parent_dir(path: &Path) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("creating directory {}", parent.display()))?;
    }
    Ok(())
}

/// Collects `--input_file` and `--input_file_list` entries into archive-path-sorted
/// `(package_path, real_path)` pairs (later entries win on duplicate `package_path` keys,
/// matching `tools/wheelmaker.py`).
///
/// Each `package_path` is relative to the wheel root before prefix rewriting; each `real_path` is
/// relative to CWD or absolute.
fn collect_sorted_inputs(options: &Options) -> Result<Vec<(String, PathBuf)>> {
    let mut files: HashMap<String, PathBuf> = options.input_file.iter().cloned().collect();
    for list_path in &options.input_file_list {
        let content = read_text(list_path)?;
        for line in content.lines() {
            if line.is_empty() {
                continue;
            }
            let Some((pkg, real)) = line.split_once(';') else {
                bail!(
                    "invalid line in input_file_list {} \
                     (expected 'package_path;real_path'): {line:?}",
                    list_path.display()
                );
            };
            files.insert(pkg.to_string(), PathBuf::from(real));
        }
    }
    let mut sorted_files: Vec<(String, PathBuf)> = files.into_iter().collect();
    // Sort the files for reproducible order in the archive.
    sorted_files.sort_unstable_by(|a, b| a.0.cmp(&b.0));
    Ok(sorted_files)
}

/// Resolves `{KEY}` workspace status stamps in `options.name` and `options.version` when both
/// volatile and stable status files are provided (matching `tools/wheelmaker.py`).
fn resolve_name_and_version(options: &Options) -> Result<(String, String)> {
    let (Some(volatile_path), Some(stable_path)) =
        (&options.volatile_status_file, &options.stable_status_file)
    else {
        return Ok((options.name.clone(), options.version.clone()));
    };
    let volatile_text = read_text(volatile_path)?;
    let stable_text = read_text(stable_path)?;
    let status_lines: Vec<String> = volatile_text
        .lines()
        .chain(stable_text.lines())
        .map(ToString::to_string)
        .collect();
    Ok((
        resolve_stamp_with_lines(&options.name, &status_lines),
        resolve_stamp_with_lines(&options.version, &status_lines),
    ))
}

/// Builds the `.whl` archive and optional `--name_file` according to `options`.
pub fn build_wheel(options: &Options) -> Result<()> {
    let sorted_files = collect_sorted_inputs(options)?;
    let (name, version) = resolve_name_and_version(options)?;
    let maker = WheelMaker::new(&name, &version, options)?;

    let out_path = maker.filename();
    create_parent_dir(&out_path)?;
    let out_file = BufWriter::with_capacity(
        BLOCK_SIZE,
        File::create(&out_path)
            .with_context(|| format!("creating wheel {}", out_path.display()))?,
    );
    let mut whl = maker.open_whlfile(out_file);

    for (package_filename, real_filename) in &sorted_files {
        whl.add_file(package_filename, real_filename)?;
    }

    let wheel_contents = maker.wheelfile_contents();
    whl.add_string(&maker.distinfo_path("WHEEL"), wheel_contents.as_bytes())?;

    let description = options
        .description_file
        .as_deref()
        .map(read_text)
        .transpose()?;

    let raw_metadata = read_text(&options.metadata_file)?;
    let expanded_metadata = expand_metadata_requires(&raw_metadata)?;
    let final_metadata = maker.format_metadata(&expanded_metadata, description.as_deref())?;
    whl.add_string(&maker.distinfo_path("METADATA"), final_metadata.as_bytes())?;

    if let Some(ref ep_path) = options.entry_points_file {
        whl.add_file(&maker.distinfo_path("entry_points.txt"), ep_path)?;
    }

    // Sort data and extra dist-info files for reproducible order in the archive.
    let mut data_files = options.data_files.clone();
    data_files.sort_unstable();
    for (filename, real_path) in &data_files {
        whl.add_file(&maker.data_path(filename), real_path)?;
    }

    let mut extra_distinfo_file = options.extra_distinfo_file.clone();
    extra_distinfo_file.sort_unstable();
    for (filename, real_path) in &extra_distinfo_file {
        whl.add_file(&maker.distinfo_path(filename), real_path)?;
    }

    whl.add_recordfile()?;
    whl.finish()
        .with_context(|| format!("finalizing wheel {}", out_path.display()))?;

    // Since stamping may change the target name of the wheel, write the canonical name (with
    // stamps resolved) to `--name_file` so downstream consumers can determine the stamped name.
    if let Some(ref name_file_path) = options.name_file {
        create_parent_dir(name_file_path)?;
        fs::write(name_file_path, maker.wheelname())
            .with_context(|| format!("writing name_file {}", name_file_path.display()))?;
    }

    Ok(())
}

fn parse_target_path_pair(raw: &str) -> std::result::Result<(String, PathBuf), String> {
    let (target, real_path) = raw
        .split_once(';')
        .ok_or_else(|| format!("expected 'target;real_path' pair, got {raw:?}"))?;
    Ok((target.to_string(), PathBuf::from(real_path)))
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

    let mut name: Option<String> = None;
    let mut version: Option<String> = None;
    let mut build_tag = String::new();
    let mut python_tag = "py3".to_string();
    let mut abi = "none".to_string();
    let mut platform = "any".to_string();
    let mut out: Option<PathBuf> = None;
    let mut no_compress = false;
    let mut name_file: Option<PathBuf> = None;
    let mut strip_path_prefixes: Vec<String> = Vec::new();
    let mut path_prefix = String::new();
    let mut metadata_file: Option<PathBuf> = None;
    let mut description_file: Option<PathBuf> = None;
    let mut entry_points_file: Option<PathBuf> = None;
    let mut input_file: Vec<(String, PathBuf)> = Vec::new();
    let mut input_file_list: Vec<PathBuf> = Vec::new();
    let mut extra_distinfo_file: Vec<(String, PathBuf)> = Vec::new();
    let mut data_files: Vec<(String, PathBuf)> = Vec::new();
    let mut volatile_status_file: Option<PathBuf> = None;
    let mut stable_status_file: Option<PathBuf> = None;

    let mut parser = lexopt::Parser::from_args(expanded);
    while let Some(arg) = parser.next()? {
        match arg {
            Short(flags::HELP_SHORT) | Long(flags::HELP) => return Ok(Cli::Help),
            Long(flags::NAME) => {
                name = Some(parser.value()?.string()?);
            }
            Long(flags::VERSION) => {
                version = Some(parser.value()?.string()?);
            }
            Long(flags::BUILD_TAG) => {
                build_tag = parser.value()?.string()?;
            }
            Long(flags::PYTHON_TAG) => {
                python_tag = parser.value()?.string()?;
            }
            Long(flags::ABI) => {
                abi = parser.value()?.string()?;
            }
            Long(flags::PLATFORM) => {
                platform = parser.value()?.string()?;
            }
            Long(flags::OUT) => {
                out = Some(PathBuf::from(parser.value()?));
            }
            Long(flags::NO_COMPRESS) => {
                no_compress = true;
            }
            Long(flags::NAME_FILE) => {
                name_file = Some(PathBuf::from(parser.value()?));
            }
            Long(flags::STRIP_PATH_PREFIX) => {
                strip_path_prefixes.push(parser.value()?.string()?);
            }
            Long(flags::PATH_PREFIX) => {
                path_prefix = parser.value()?.string()?;
            }
            Long(flags::METADATA_FILE) => {
                metadata_file = Some(PathBuf::from(parser.value()?));
            }
            Long(flags::DESCRIPTION_FILE) => {
                description_file = Some(PathBuf::from(parser.value()?));
            }
            Long(flags::ENTRY_POINTS_FILE) => {
                entry_points_file = Some(PathBuf::from(parser.value()?));
            }
            Long(flags::INPUT_FILE) => {
                input_file.push(parser.value()?.parse_with(parse_target_path_pair)?);
            }
            Long(flags::INPUT_FILE_LIST) => {
                input_file_list.push(PathBuf::from(parser.value()?));
            }
            Long(flags::EXTRA_DISTINFO_FILE) => {
                extra_distinfo_file.push(parser.value()?.parse_with(parse_target_path_pair)?);
            }
            Long(flags::DATA_FILES) => {
                data_files.push(parser.value()?.parse_with(parse_target_path_pair)?);
            }
            Long(flags::VOLATILE_STATUS_FILE) => {
                volatile_status_file = Some(PathBuf::from(parser.value()?));
            }
            Long(flags::STABLE_STATUS_FILE) => {
                stable_status_file = Some(PathBuf::from(parser.value()?));
            }
            _ => bail!("{}", arg.unexpected()),
        }
    }

    let name = name.with_context(|| format!("missing required argument: --{}", flags::NAME))?;
    let version =
        version.with_context(|| format!("missing required argument: --{}", flags::VERSION))?;
    let metadata_file = metadata_file
        .with_context(|| format!("missing required argument: --{}", flags::METADATA_FILE))?;

    Ok(Cli::Run(Box::new(Options {
        name,
        version,
        build_tag,
        python_tag,
        abi,
        platform,
        out,
        no_compress,
        name_file,
        strip_path_prefixes,
        path_prefix,
        metadata_file,
        description_file,
        entry_points_file,
        input_file,
        input_file_list,
        extra_distinfo_file,
        data_files,
        volatile_status_file,
        stable_status_file,
    })))
}

/// Parses CLI arguments (excluding `argv[0]` and subcommand name), builds the wheel, and returns
/// the process exit code.
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
            eprintln!("wheelmaker: error: {err:#}");
            return ExitCode::FAILURE;
        }
    };
    if let Err(err) = build_wheel(&options) {
        eprintln!("wheelmaker: error: {err:#}");
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}

/// Low-level `.whl` zip archive writer that records `(path, sha256, size)` entries for `RECORD`,
/// mirroring `_WhlFile` in `tools/wheelmaker.py`.
pub struct WhlFile<W: Write + Seek> {
    zip: ZipWriter<W>,
    compress: bool,
    distribution_prefix: String,
    strip_path_prefixes: Vec<String>,
    add_path_prefix: String,
    buf: Vec<u8>,
    /// Recorded `(arcname, digest, size)` tuples where `arcname` is relative to the wheel root.
    record: Vec<(String, String, String)>,
}

impl<W: Write + Seek> WhlFile<W> {
    /// Creates a new `.whl` archive writer over `writer`.
    pub fn new(
        writer: W,
        distribution_prefix: &str,
        strip_path_prefixes: Vec<String>,
        add_path_prefix: &str,
        compress: bool,
    ) -> Self {
        Self {
            zip: ZipWriter::new(writer),
            compress,
            distribution_prefix: distribution_prefix.to_string(),
            strip_path_prefixes,
            add_path_prefix: add_path_prefix.to_string(),
            buf: vec![0u8; BLOCK_SIZE],
            record: Vec::new(),
        }
    }

    fn distinfo_path(&self, basename: &str) -> String {
        format!("{}.dist-info/{basename}", self.distribution_prefix)
    }

    fn clean_zip_arcname(filename: &str) -> &str {
        // Strip leading path separators to mirror `ZipInfo.from_file` / `_WhlFile._zipinfo`.
        filename.trim_start_matches(['/', '\\'])
    }

    fn file_options(&self, size: u64) -> SimpleFileOptions {
        let method = if self.compress {
            CompressionMethod::Deflated
        } else {
            CompressionMethod::Stored
        };
        // Use `System::Unix` (`create_system = 3`) so `zip` preserves `unix_permissions` on
        // Windows too instead of synthesizing MS-DOS attributes.
        SimpleFileOptions::default()
            .compression_method(method)
            .last_modified_time(FIXED_TIMESTAMP)
            .system(System::Unix)
            .unix_permissions(REGULAR_FILE_UNIX_MODE)
            .large_file(size >= ZIP64_BYTES_THR)
    }

    /// Copies `real_filename` (a file or directory, relative to CWD or absolute) into the wheel
    /// under `package_filename` (relative to the archive root before prefix rewriting).
    pub fn add_file(&mut self, package_filename: &str, real_filename: &Path) -> Result<()> {
        if real_filename.is_dir() {
            let mut entries = Vec::new();
            for entry in fs::read_dir(real_filename)
                .with_context(|| format!("reading directory {}", real_filename.display()))?
            {
                let entry = entry.with_context(|| {
                    format!("reading directory entry in {}", real_filename.display())
                })?;
                let Ok(file_name) = entry.file_name().into_string() else {
                    bail!(
                        "non-UTF-8 filename in input directory {}: {:?}",
                        real_filename.display(),
                        entry.file_name()
                    );
                };
                entries.push((file_name, entry.path()));
            }
            // Sort directory entries for reproducible order in the archive.
            entries.sort_by(|a, b| a.0.cmp(&b.0));
            for (file_name, path) in entries {
                let child_pkg = format!("{package_filename}/{file_name}");
                self.add_file(&child_pkg, &path)?;
            }
            return Ok(());
        }

        let arcname = arcname_from(
            package_filename,
            &self.distribution_prefix,
            &self.strip_path_prefixes,
            &self.add_path_prefix,
        );
        let zip_arcname = Self::clean_zip_arcname(&arcname);

        let mut src = File::open(real_filename)
            .with_context(|| format!("opening input file {}", real_filename.display()))?;
        let initial_len = src
            .metadata()
            .with_context(|| format!("reading metadata for {}", real_filename.display()))?
            .len();
        let opts = self.file_options(initial_len);
        self.zip
            .start_file(zip_arcname, opts)
            .with_context(|| format!("starting zip entry {zip_arcname}"))?;

        // Write file to the zip archive while computing its SHA-256 digest and byte length.
        let mut sha = Sha256::new();
        let mut size: u64 = 0;
        loop {
            let n = src
                .read(&mut self.buf)
                .with_context(|| format!("reading input file {}", real_filename.display()))?;
            if n == 0 {
                break;
            }
            self.zip
                .write_all(&self.buf[..n])
                .with_context(|| format!("writing zip entry {zip_arcname}"))?;
            sha.update(&self.buf[..n]);
            size += n as u64;
        }

        let digest = serialize_digest(&sha.finalize());
        self.record
            .push((zip_arcname.to_string(), digest, size.to_string()));
        Ok(())
    }

    /// Writes in-memory `contents` as `filename` (relative to the archive root) and records its
    /// SHA-256 digest and byte length.
    pub fn add_string(&mut self, filename: &str, contents: &[u8]) -> Result<()> {
        let zip_arcname = Self::clean_zip_arcname(filename);
        let opts = self.file_options(contents.len() as u64);
        self.zip
            .start_file(zip_arcname, opts)
            .with_context(|| format!("starting zip entry {zip_arcname}"))?;
        self.zip
            .write_all(contents)
            .with_context(|| format!("writing zip entry {zip_arcname}"))?;

        let mut sha = Sha256::new();
        sha.update(contents);
        let digest = serialize_digest(&sha.finalize());
        self.record
            .push((zip_arcname.to_string(), digest, contents.len().to_string()));
        Ok(())
    }

    /// Formats and writes `<dist-info>/RECORD` using minimal CSV quoting, returning the written
    /// `RECORD` text.
    pub fn add_recordfile(&mut self) -> Result<String> {
        let record_path = self.distinfo_path("RECORD");
        // Quote only when necessary (e.g. for filenames with commas).
        let mut wtr = csv::WriterBuilder::new()
            .has_headers(false)
            .terminator(csv::Terminator::Any(b'\n'))
            .quote_style(csv::QuoteStyle::Necessary)
            .from_writer(Vec::new());
        for (fname, digest, size) in &self.record {
            wtr.write_record([fname.as_str(), digest.as_str(), size.as_str()])
                .context("formatting RECORD entry as CSV")?;
        }
        wtr.write_record([Self::clean_zip_arcname(&record_path), "", ""])
            .context("formatting RECORD self-entry as CSV")?;
        let bytes = wtr.into_inner().context("flushing RECORD CSV buffer")?;
        let contents = String::from_utf8(bytes).context("RECORD CSV was not valid UTF-8")?;
        self.add_string(&record_path, contents.as_bytes())?;
        Ok(contents)
    }

    /// Finalizes the underlying zip archive and flushes `W`.
    pub fn finish(self) -> Result<W> {
        let mut inner = self.zip.finish().context("writing zip central directory")?;
        inner.flush().context("flushing zip writer")?;
        Ok(inner)
    }
}

/// High-level wheel builder mirroring `WheelMaker` in `tools/wheelmaker.py`.
pub struct WheelMaker {
    name: String,
    version: String,
    build_tag: String,
    python_tag: String,
    abi: String,
    platform: String,
    /// Explicit output `.whl` path relative to CWD or absolute, if `--out` was given.
    outfile: Option<PathBuf>,
    strip_path_prefixes: Vec<String>,
    add_path_prefix: String,
    compress: bool,
    wheelname_fragment_distribution_name: String,
    distribution_prefix: String,
}

impl WheelMaker {
    /// Creates a `WheelMaker` with resolved `name` and `version` (after any workspace status
    /// stamping) and the remaining wheel settings from `options`.
    pub fn new(name: &str, version: &str, options: &Options) -> Result<Self> {
        let norm_version = normalize_pep440(version)?;
        let wheelname_fragment_distribution_name = escape_filename_distribution_name(name)?;
        let distribution_prefix = format!("{wheelname_fragment_distribution_name}-{norm_version}");
        Ok(Self {
            name: name.to_string(),
            version: norm_version,
            build_tag: options.build_tag.clone(),
            python_tag: options.python_tag.clone(),
            abi: options.abi.clone(),
            platform: options.platform.clone(),
            outfile: options.out.clone(),
            strip_path_prefixes: options.strip_path_prefixes.clone(),
            add_path_prefix: options.path_prefix.clone(),
            compress: !options.no_compress,
            wheelname_fragment_distribution_name,
            distribution_prefix,
        })
    }

    /// Returns the canonical PEP 427 wheel filename
    /// (`<dist>-<ver>[-<build>]-<py>-<abi>-<plat>.whl`).
    pub fn wheelname(&self) -> String {
        let mut components = vec![
            self.wheelname_fragment_distribution_name.as_str(),
            self.version.as_str(),
        ];
        if !self.build_tag.is_empty() {
            components.push(self.build_tag.as_str());
        }
        components.extend([
            self.python_tag.as_str(),
            self.abi.as_str(),
            self.platform.as_str(),
        ]);
        format!("{}.whl", components.join("-"))
    }

    /// Returns the output `.whl` path (either `--out` or [`Self::wheelname`] relative to CWD).
    pub fn filename(&self) -> PathBuf {
        if let Some(ref out) = self.outfile {
            out.clone()
        } else {
            PathBuf::from(self.wheelname())
        }
    }

    /// Returns the compatibility tags written to `<dist-info>/WHEEL`.
    pub fn disttags(&self) -> Vec<String> {
        vec![format!(
            "{}-{}-{}",
            self.python_tag, self.abi, self.platform
        )]
    }

    /// Returns `<distribution_prefix>.dist-info/<basename>` relative to the archive root.
    pub fn distinfo_path(&self, basename: &str) -> String {
        format!("{}.dist-info/{basename}", self.distribution_prefix)
    }

    /// Returns `<distribution_prefix>.data/<basename>` relative to the archive root.
    pub fn data_path(&self, basename: &str) -> String {
        format!("{}.data/{basename}", self.distribution_prefix)
    }

    /// Formats the `<dist-info>/WHEEL` metadata file contents.
    pub fn wheelfile_contents(&self) -> String {
        // TODO(pstradomski): Support non-purelib wheels.
        let purelib = if self.platform == "any" {
            "true"
        } else {
            "false"
        };
        let mut contents = format!(
            "Wheel-Version: 1.0\nGenerator: bazel-wheelmaker 1.0\nRoot-Is-Purelib: {purelib}\n"
        );
        for tag in self.disttags() {
            contents.push_str(&format!("Tag: {tag}\n"));
        }
        contents
    }

    /// Formats the `<dist-info>/METADATA` contents per PEP 566 / Core Metadata.
    ///
    /// See <https://peps.python.org/pep-0566/> and
    /// <https://packaging.python.org/en/latest/specifications/core-metadata/>.
    pub fn format_metadata(&self, metadata: &str, description: Option<&str>) -> Result<String> {
        let name_re = Regex::new(r"(?m)^Name: .*$")?;
        let replacement = format!("Name: {}", self.name);
        let mut out = name_re
            .replace_all(metadata, regex::NoExpand(&replacement))
            .into_owned();
        out.push_str(&format!("Version: {}\n\n", self.version));
        // setuptools inserts `UNKNOWN` as the description when none is provided.
        match description {
            Some(desc) if !desc.is_empty() => {
                // Normalize CRLF on Windows while appending directly into `out`.
                for (i, chunk) in desc.split("\r\n").enumerate() {
                    if i > 0 {
                        out.push('\n');
                    }
                    out.push_str(chunk);
                }
            }
            _ => out.push_str("UNKNOWN"),
        }
        out.push('\n');
        Ok(out)
    }

    /// Opens a [`WhlFile`] configured with this wheel's prefix and compression settings.
    pub fn open_whlfile<W: Write + Seek>(&self, writer: W) -> WhlFile<W> {
        WhlFile::new(
            writer,
            &self.distribution_prefix,
            self.strip_path_prefixes.clone(),
            &self.add_path_prefix,
            self.compress,
        )
    }
}

/// Result of parsing the command line.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Cli {
    /// `--help` was requested.
    Help,
    /// Build a wheel archive with the given options.
    Run(Box<Options>),
}

/// Parsed command-line options for `wheelmaker`.
///
/// All `PathBuf` fields hold filesystem paths relative to the current working directory or
/// absolute; archive destination strings in `(String, PathBuf)` pairs are relative to the archive
/// root, `.dist-info/`, or `.data/` respectively.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Options {
    /// Distribution name (may contain `{KEY}` stamp placeholders).
    pub name: String,
    /// Distribution version string (may contain `{KEY}` stamp placeholders).
    pub version: String,
    /// Optional PEP 427 build tag.
    pub build_tag: String,
    /// Python implementation/version tag (e.g. `py3`, `cp311`).
    pub python_tag: String,
    /// Python ABI tag (e.g. `none`, `abi3`).
    pub abi: String,
    /// Target platform tag (e.g. `any`, `manylinux2014_x86_64`).
    pub platform: String,
    /// Optional output `.whl` file path, relative to CWD or absolute.
    pub out: Option<PathBuf>,
    /// When `true`, store archive entries uncompressed (`ZIP_STORED`).
    pub no_compress: bool,
    /// Optional output file where the canonical wheel filename is written, relative to CWD or
    /// absolute.
    pub name_file: Option<PathBuf>,
    /// Path prefixes stripped in order from archive entry paths.
    pub strip_path_prefixes: Vec<String>,
    /// Path prefix prepended to archive entry paths after stripping.
    pub path_prefix: String,
    /// Path to the pre-formatted `METADATA` header file, relative to CWD or absolute.
    pub metadata_file: PathBuf,
    /// Optional path to the package description file, relative to CWD or absolute.
    pub description_file: Option<PathBuf>,
    /// Optional path to `entry_points.txt`, relative to CWD or absolute.
    pub entry_points_file: Option<PathBuf>,
    /// `(archive_path, filesystem_path)` pairs added to the wheel root.
    pub input_file: Vec<(String, PathBuf)>,
    /// Paths to files containing newline-delimited `archive_path;filesystem_path` pairs, relative
    /// to CWD or absolute.
    pub input_file_list: Vec<PathBuf>,
    /// `(distinfo_rel_path, filesystem_path)` pairs added under `<dist-info>/`.
    pub extra_distinfo_file: Vec<(String, PathBuf)>,
    /// `(data_rel_path, filesystem_path)` pairs added under `<data>/`.
    pub data_files: Vec<(String, PathBuf)>,
    /// Optional volatile Bazel workspace status file, relative to CWD or absolute.
    pub volatile_status_file: Option<PathBuf>,
    /// Optional stable Bazel workspace status file, relative to CWD or absolute.
    pub stable_status_file: Option<PathBuf>,
}

//! Library supporting creating deterministic zipapp archives from a manifest.

// Errors must be returned, not panicked; see `--config=rust-lint` in .bazelrc.
#![deny(clippy::expect_used, clippy::unwrap_used)]

use std::collections::HashSet;
use std::ffi::OsString;
use std::fs::{self, File, Metadata};
use std::io::{self, BufWriter, Seek, Write};
use std::path::{Path, PathBuf};

use anyhow::{bail, Context, Result};
use zip::write::SimpleFileOptions;
use zip::{CompressionMethod, DateTime, ZipWriter, ZIP64_BYTES_THR};

/// `BufWriter` capacity for the output zip.
///
/// 256 KiB matches the other zipapp tools (`exe_zip_maker`, `zip_main_maker.py`). It is large
/// enough that the many small entries of a typical zipapp coalesce into few `write` syscalls,
/// while staying well below sizes where a bigger buffer stops paying off.
const BLOCK_SIZE: usize = 256 * 1024;

/// Usage text for `--help`. `lexopt` does not generate help, so this is maintained by hand.
const USAGE: &str = "\
Usage: zipper [OPTIONS] <manifest> <output>

Create a zip file from a manifest.

Arguments:
  <manifest>  Path to the manifest file. Line formats are documented on
              `parse_entry` in crates/zipper/src/lib.rs.
  <output>    Path to the output zip file

Options:
  --compression <N>                  Compression level (0 for stored, 1-9 for deflated) [default: 0]
  --workspace-name <NAME>            Name of the workspace [default: \"\"]
  --legacy-external-runfiles <0|1>   Whether to use legacy external runfiles behavior [default: 0]
  --runfiles-dir <DIR>               Name of the runfiles directory [default: runfiles]
  --target-platform-pathsep <SEP>    Path separator for the target platform [default: host separator]
  -h, --help                         Print this help";

/// Joins path components with `/`.
fn unix_join(parts: &[&str]) -> String {
    parts.join("/")
}

/// Computes the zip path (relative to the zip root) for a runfile entry.
fn get_zip_runfiles_path(
    path: &str,
    workspace_name: &str,
    legacy_external_runfiles: bool,
    runfiles_dir: &str,
) -> String {
    if legacy_external_runfiles {
        if let Some(rest) = path.strip_prefix("external/") {
            return unix_join(&[runfiles_dir, rest]);
        }
    }
    if let Some(rest) = path.strip_prefix("../") {
        return unix_join(&[runfiles_dir, rest]);
    }
    unix_join(&[runfiles_dir, workspace_name, path])
}

/// Splits `path` into its components, dropping empty components and `.`, and resolving `..`
/// against the preceding component where possible (a leading run of `..` is kept, since there
/// is nothing to cancel it against).
///
/// Both `/` and `\` are treated as separators so the result is the same on every host.
/// For example, `a/./b\c/../d` becomes `["a", "b", "d"]`, and `../x` becomes `["..", "x"]`.
fn normalize_components(path: &str) -> Vec<&str> {
    let mut out = Vec::new();
    for part in path.split(['/', '\\']) {
        if part.is_empty() || part == "." {
            continue;
        }
        if part == ".." {
            if let Some(&last) = out.last() {
                if last != ".." {
                    out.pop();
                    continue;
                }
            }
            out.push("..");
        } else {
            out.push(part);
        }
    }
    out
}

/// Computes a relative path from `start` directory to `target` using `/` separators,
/// matching `os.path.relpath(target, start=start)`.
///
/// This is hand-rolled rather than using `std::path` because `Path` semantics depend on the
/// host OS (e.g. `\` is not a separator on Unix, and output uses `\` on Windows), whereas zip
/// entry paths must be computed identically on every host.
pub fn relative_path(target: &str, start: &str) -> String {
    let start_parts = normalize_components(start);
    let target_parts = normalize_components(target);
    let common = start_parts
        .iter()
        .zip(target_parts.iter())
        .take_while(|(a, b)| a == b)
        .count();

    let mut result = vec![".."; start_parts.len() - common];
    result.extend_from_slice(&target_parts[common..]);
    if result.is_empty() {
        ".".to_string()
    } else {
        result.join("/")
    }
}

/// Converts a symlink target path to the target-platform format.
///
/// On Windows, relative symlinks must use backslashes.
fn convert_symlink_target(path: &str, platform_pathsep: &str) -> String {
    if platform_pathsep == "/" {
        // Convert Windows to Unix
        path.replace('\\', "/")
    } else {
        // Convert Unix to Windows
        path.replace('/', "\\")
    }
}

/// Normalizes zip entry paths (relative to the zip root) to use forward slashes.
///
/// Zip files use forward slash for the entries, even on Windows.
fn normalize_zip_path(path: &str) -> String {
    path.replace('\\', "/")
}

/// Parses the `is_symlink` field of a manifest line.
fn parse_symlink_mode(value: &str) -> Result<SymlinkMode> {
    match value {
        "0" => Ok(SymlinkMode::Regular),
        "1" => Ok(SymlinkMode::Symlink),
        "-1" => Ok(SymlinkMode::Infer),
        _ => bail!("invalid is_symlink value (expected 0, 1, or -1): {value}"),
    }
}

/// Parses a single line of a manifest file. Returns `None` for blank lines.
///
/// Lines have one of the following `|`-separated formats:
///
/// * `regular|is_symlink|zip_path|content_path`: Stores `zip_path` at the exact
///   zip-root-relative path given, reading its content (or symlink target) from `content_path`.
/// * `rf-empty|runfile_path`: A `runfiles.empty_filenames` entry (such as an implicit
///   `__init__.py`) stored as an empty file under `<runfiles_dir>/<runfiles_root_rel_path>`.
/// * `rf-file|is_symlink|runfile_path|content_path`: A `runfiles.files` entry whose destination
///   zip path is computed under `<runfiles_dir>` from `runfile_path` (accounting for
///   `workspace_name` and `legacy_external_runfiles`), reading content from `content_path`.
/// * `rf-symlink|is_symlink|runfile_symlink_path|content_path`: A `runfiles.symlinks` entry
///   stored under `<runfiles_dir>/<workspace_name>/<runfile_symlink_path>`, reading content
///   from `content_path`.
/// * `rf-root-symlink|is_symlink|runfile_root_path|content_path`: A `runfiles.root_symlinks`
///   entry stored under `<runfiles_dir>/<runfile_root_path>`, reading content from
///   `content_path`.
/// * `symlink|runfile_root_path|link_to_rf_path`: An explicit symlink entry stored at
///   `<runfiles_dir>/<runfile_root_path>` whose symlink target is computed as the relative path
///   from its parent directory to `<runfiles_dir>/<link_to_rf_path>`. Takes precedence over
///   non-symlink entries at the same `zip_path`.
///
/// See [`SymlinkMode`] for the valid `is_symlink` values.
fn parse_entry(
    line: &str,
    workspace_name: &str,
    legacy_external_runfiles: bool,
    runfiles_dir: &str,
) -> Result<Option<ManifestEntry>> {
    let line = line.trim();
    if line.is_empty() {
        return Ok(None);
    }

    // Closures (not values): `file(...)` builds a `File` entry and `rf_path(...)` computes a
    // runfiles zip path. They capture the function arguments so the match arms stay short.
    let file = |content_path: &str, is_symlink: &str| -> Result<EntryKind> {
        Ok(EntryKind::File {
            content_path: PathBuf::from(content_path),
            symlink_mode: parse_symlink_mode(is_symlink)?,
        })
    };
    let rf_path = |runfile_path: &str| {
        get_zip_runfiles_path(
            runfile_path,
            workspace_name,
            legacy_external_runfiles,
            runfiles_dir,
        )
    };

    let parts: Vec<&str> = line.split('|').collect();
    let entry = match parts.as_slice() {
        ["regular", is_symlink, zip_path, content_path] => ManifestEntry {
            zip_path: zip_path.to_string(),
            kind: file(content_path, is_symlink)?,
        },
        ["rf-empty", runfile_path] => ManifestEntry {
            zip_path: rf_path(runfile_path),
            kind: EntryKind::Empty,
        },
        ["rf-file", is_symlink, runfile_path, content_path] => ManifestEntry {
            zip_path: rf_path(runfile_path),
            kind: file(content_path, is_symlink)?,
        },
        ["rf-symlink", is_symlink, runfile_path, content_path] => ManifestEntry {
            zip_path: unix_join(&[runfiles_dir, workspace_name, runfile_path]),
            kind: file(content_path, is_symlink)?,
        },
        ["rf-root-symlink", is_symlink, runfile_path, content_path] => ManifestEntry {
            zip_path: unix_join(&[runfiles_dir, runfile_path]),
            kind: file(content_path, is_symlink)?,
        },
        ["symlink", runfile_path, link_to_rf_path] => {
            let zip_path = unix_join(&[runfiles_dir, runfile_path]);
            let link_to = unix_join(&[runfiles_dir, link_to_rf_path]);
            let parent = zip_path.rsplit_once('/').map_or("", |(dir, _)| dir);
            let target = relative_path(&link_to, parent);
            ManifestEntry {
                zip_path,
                kind: EntryKind::Symlink { target },
            }
        }
        _ => bail!("unknown entry type or invalid format: {line}"),
    };

    Ok(Some(entry))
}

fn sort_key(entry: &ManifestEntry) -> (&str, bool) {
    // Sort by zip path, then symlink entries first so they have precedence.
    (
        &entry.zip_path,
        !matches!(entry.kind, EntryKind::Symlink { .. }),
    )
}

/// Reads and sorts all entries from the manifest file at `manifest_path`.
fn read_manifest(options: &ZipOptions) -> Result<Vec<ManifestEntry>> {
    let content = fs::read_to_string(&options.manifest_path)
        .with_context(|| format!("reading manifest {}", options.manifest_path.display()))?;
    let mut entries = Vec::new();
    for (line_idx, line) in content.lines().enumerate() {
        let parsed = parse_entry(
            line,
            &options.workspace_name,
            options.legacy_external_runfiles,
            &options.runfiles_dir,
        )
        .with_context(|| format!("manifest line {}", line_idx + 1))?;
        if let Some(entry) = parsed {
            entries.push(entry);
        }
    }
    entries.sort_by(|a, b| sort_key(a).cmp(&sort_key(b)));
    Ok(entries)
}

fn is_symlink_path(path: &Path) -> bool {
    fs::symlink_metadata(path)
        .map(|m| m.file_type().is_symlink())
        .unwrap_or(false)
}

fn is_abs_path(path: &Path) -> bool {
    if path.is_absolute() {
        return true;
    }
    // On Windows, `is_absolute()` requires a drive prefix, so rooted-but-driveless paths
    // (`\foo`, `/foo`) are reported as relative. Such paths still only resolve on the build
    // machine, so treat them as absolute too.
    let s = path.to_string_lossy();
    s.starts_with('/') || s.starts_with('\\')
}

fn read_link_string(path: &Path) -> Result<String> {
    let target =
        fs::read_link(path).with_context(|| format!("reading symlink {}", path.display()))?;
    Ok(target.to_string_lossy().into_owned())
}

/// Determines whether `content_path` should be stored as a symlink and returns its target
/// (relative to the symlink's parent directory).
fn source_symlink_target(content_path: &Path, symlink_mode: SymlinkMode) -> Result<Option<String>> {
    let symlink_mode = match symlink_mode {
        SymlinkMode::Infer if fs::metadata(content_path).is_err() => SymlinkMode::Symlink,
        SymlinkMode::Infer => SymlinkMode::Regular,
        mode => mode,
    };
    if symlink_mode == SymlinkMode::Symlink {
        return Ok(Some(read_link_string(content_path)?));
    }
    if !is_symlink_path(content_path) {
        return Ok(None);
    }

    let target = fs::read_link(content_path)
        .with_context(|| format!("reading symlink {}", content_path.display()))?;
    if !is_abs_path(&target) {
        return Ok(Some(target.to_string_lossy().into_owned()));
    }

    // Bazel sandboxes expose regular inputs as absolute symlinks. Look through
    // that indirection to detect whether the original source is also a symlink.
    // Only a relative link can be kept: an absolute one points into this
    // machine's Bazel output base (e.g. the _solib links Bazel creates for shared
    // libraries) and would dangle wherever the zipapp runs, so store the file.
    if is_symlink_path(&target) {
        let source_target = fs::read_link(&target)
            .with_context(|| format!("reading symlink {}", target.display()))?;
        if !is_abs_path(&source_target) {
            return Ok(Some(source_target.to_string_lossy().into_owned()));
        }
    }
    Ok(None)
}

/// Returns the Unix permission bits (`0o777` mask) to store for a file.
///
/// The zip crate's `unix_permissions()` keeps only the permission bits and sets the file type
/// itself, so special bits (setuid, setgid, sticky) are not preserved.
fn mode_from_metadata(meta: &Metadata) -> u32 {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        meta.permissions().mode()
    }
    // `not(unix)` (rather than `windows`) so every target has a definition.
    #[cfg(not(unix))]
    {
        // Mirrors what Python's `os.stat` reports on Windows.
        if meta.permissions().readonly() {
            0o444
        } else {
            0o666
        }
    }
}

/// Fixed timestamp for all entries so output is deterministic. This is the earliest
/// MS-DOS timestamp a zip can represent and matches the Python implementation.
fn fixed_timestamp() -> DateTime {
    DateTime::DEFAULT
}

fn file_options(compress_level: u32, unix_mode: u32) -> SimpleFileOptions {
    let options = SimpleFileOptions::default()
        .last_modified_time(fixed_timestamp())
        .unix_permissions(unix_mode);
    if compress_level == 0 {
        options.compression_method(CompressionMethod::Stored)
    } else {
        options
            .compression_method(CompressionMethod::Deflated)
            .compression_level(Some(i64::from(compress_level)))
    }
}

/// Options for symlink entries. `add_symlink` already sets `0o777 | S_IFLNK` and always stores
/// symlinks uncompressed, so only the timestamp needs fixing.
fn symlink_options() -> SimpleFileOptions {
    SimpleFileOptions::default().last_modified_time(fixed_timestamp())
}

fn write_entry<W: Write + Seek>(
    zf: &mut ZipWriter<W>,
    entry: &ManifestEntry,
    options: &ZipOptions,
    seen: &mut HashSet<String>,
) -> Result<()> {
    // Normalize slashes, otherwise the `seen` logic doesn't work correctly.
    let zip_path = normalize_zip_path(&entry.zip_path);
    if !seen.insert(zip_path.clone()) {
        // This can occur because symlink entries have precedence over non-symlink entries.
        return Ok(());
    }

    let (content_path, symlink_mode) = match &entry.kind {
        EntryKind::Empty => {
            // Create empty file
            zf.start_file(&zip_path, file_options(options.compress_level, 0o644))
                .with_context(|| format!("adding {zip_path}"))?;
            return Ok(());
        }
        EntryKind::Symlink { target } => {
            let target = convert_symlink_target(target, &options.platform_pathsep);
            zf.add_symlink(&zip_path, target, symlink_options())
                .with_context(|| format!("adding {zip_path}"))?;
            return Ok(());
        }
        EntryKind::File {
            content_path,
            symlink_mode,
        } => (content_path, *symlink_mode),
    };

    if let Some(symlink_target) = source_symlink_target(content_path, symlink_mode)? {
        let target = convert_symlink_target(&symlink_target, &options.platform_pathsep);
        zf.add_symlink(&zip_path, target, symlink_options())
            .with_context(|| format!("adding {zip_path}"))?;
        return Ok(());
    }

    let mut src =
        File::open(content_path).with_context(|| format!("opening {}", content_path.display()))?;
    let meta = src
        .metadata()
        .with_context(|| format!("reading metadata of {}", content_path.display()))?;
    // Preserve permissions, otherwise execute is dropped.
    let mode = mode_from_metadata(&meta);
    let opts = file_options(options.compress_level, mode).large_file(meta.len() >= ZIP64_BYTES_THR);
    zf.start_file(&zip_path, opts)
        .with_context(|| format!("adding {zip_path}"))?;
    io::copy(&mut src, zf)
        .with_context(|| format!("copying {} into {zip_path}", content_path.display()))?;
    Ok(())
}

/// Creates a zip file from a manifest according to `options`.
pub fn create_zip(options: &ZipOptions) -> Result<()> {
    if options.compress_level > 9 {
        bail!(
            "invalid compress_level (expected 0-9): {}",
            options.compress_level
        );
    }
    let entries = read_manifest(options)?;

    if let Some(parent) = options.output_zip.parent() {
        // TODO: Use `Path::is_empty()` once it is stable (Rust 1.98).
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent)
                .with_context(|| format!("creating directory {}", parent.display()))?;
        }
    }

    let out_file = File::create(&options.output_zip)
        .with_context(|| format!("creating {}", options.output_zip.display()))?;
    let out_file = BufWriter::with_capacity(BLOCK_SIZE, out_file);
    let mut zf = ZipWriter::new(out_file);
    let mut seen = HashSet::new();

    for entry in &entries {
        write_entry(&mut zf, entry, options, &mut seen)?;
    }

    let mut inner = zf.finish().context("finishing zip")?;
    inner.flush().context("flushing zip")?;
    Ok(())
}

/// Parses a `0`/`1` flag value, naming `flag` in the error.
fn parse_bool_flag(flag: &str, value: &str) -> Result<bool, lexopt::Error> {
    match value {
        "0" => Ok(false),
        "1" => Ok(true),
        _ => Err(format!("invalid {flag} value (expected 0 or 1): {value}").into()),
    }
}

/// Parses command-line arguments (excluding `argv[0]`).
pub fn parse_args<I, T>(args: I) -> Result<Cli, lexopt::Error>
where
    I: IntoIterator<Item = T>,
    T: Into<OsString>,
{
    use lexopt::prelude::*;

    let mut positional: Vec<PathBuf> = Vec::new();
    let mut compress_level: u32 = 0;
    let mut workspace_name = String::new();
    let mut legacy_external_runfiles = false;
    let mut runfiles_dir = "runfiles".to_string();
    let mut platform_pathsep = std::path::MAIN_SEPARATOR_STR.to_string();

    let mut parser = lexopt::Parser::from_args(args);
    while let Some(arg) = parser.next()? {
        match arg {
            Short('h') | Long("help") => return Ok(Cli::Help),
            Long("compression") => {
                compress_level = parser.value()?.parse()?;
                if compress_level > 9 {
                    return Err(format!(
                        "invalid --compression value (expected 0-9): {compress_level}"
                    )
                    .into());
                }
            }
            Long("workspace-name") => {
                workspace_name = parser.value()?.string()?;
            }
            Long("legacy-external-runfiles") => {
                legacy_external_runfiles =
                    parse_bool_flag("--legacy-external-runfiles", &parser.value()?.string()?)?;
            }
            Long("runfiles-dir") => {
                runfiles_dir = parser.value()?.string()?;
            }
            Long("target-platform-pathsep") => {
                platform_pathsep = parser.value()?.string()?;
            }
            Value(val) => {
                positional.push(PathBuf::from(val));
            }
            _ => return Err(arg.unexpected()),
        }
    }

    let [manifest_path, output_zip]: [PathBuf; 2] =
        positional.try_into().map_err(|v: Vec<PathBuf>| {
            lexopt::Error::from(format!(
                "expected 2 positional arguments (<manifest> <output>), got {}",
                v.len()
            ))
        })?;

    Ok(Cli::Run(ZipOptions {
        manifest_path,
        output_zip,
        compress_level,
        workspace_name,
        legacy_external_runfiles,
        runfiles_dir,
        platform_pathsep,
    }))
}

/// Parses CLI arguments (excluding `argv[0]` and subcommand name), creates the zip archive, and
/// returns the process exit code.
pub fn run_cli<I, T>(args: I) -> i32
where
    I: IntoIterator<Item = T>,
    T: Into<OsString>,
{
    let options = match parse_args(args) {
        Ok(Cli::Help) => {
            println!("{USAGE}");
            return 0;
        }
        Ok(Cli::Run(opts)) => opts,
        Err(msg) => {
            eprintln!("zipper: error: {msg}");
            return 1;
        }
    };
    if let Err(err) = create_zip(&options) {
        eprintln!(
            "zipper: error creating zip {}: {err:#}",
            options.output_zip.display()
        );
        return 1;
    }
    0
}

/// Result of parsing the command line.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Cli {
    /// `--help` was requested.
    Help,
    /// Create a zip archive with the given options.
    Run(ZipOptions),
}

/// How a `File` entry's `content_path` should be stored with respect to symlinks. Parsed from
/// the `is_symlink` manifest field.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SymlinkMode {
    /// `"0"`: Store as a regular file read from `content_path` (unless `content_path` itself or
    /// its sandbox target is a relative source symlink).
    Regular,
    /// `"1"`: Store as a symlink whose target is read via `read_link(content_path)`.
    Symlink,
    /// `"-1"`: Unknown at analysis time (Bazel 7 lacks `File.is_symlink`); treated as `Symlink`
    /// when `content_path` is a dangling symlink (`fs::metadata` fails) and `Regular` otherwise.
    Infer,
}

/// What a manifest entry stores. See [`parse_entry`] for the manifest line formats.
#[derive(Debug, Clone, PartialEq, Eq)]
enum EntryKind {
    /// An empty regular file (`rf-empty`).
    Empty,
    /// A symlink whose `target` is relative to the parent directory of `zip_path` inside the
    /// zip archive (`symlink`). Takes precedence over other kinds at the same `zip_path`.
    Symlink { target: String },
    /// Content read from `content_path` on disk (relative to the current working directory or
    /// absolute), stored as a file or symlink according to `symlink_mode`.
    File {
        content_path: PathBuf,
        symlink_mode: SymlinkMode,
    },
}

/// A parsed line from a zipper manifest.
#[derive(Debug, Clone, PartialEq, Eq)]
struct ManifestEntry {
    /// Destination path inside the zip archive, relative to the zip root.
    zip_path: String,
    kind: EntryKind,
}

/// Configuration options for creating a zip archive.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ZipOptions {
    /// Path to the input manifest file, relative to the current working directory or absolute.
    pub manifest_path: PathBuf,
    /// Path to the output zip archive, relative to the current working directory or absolute.
    pub output_zip: PathBuf,
    /// ZIP compression level: `0` for uncompressed (`Stored`), or `1..=9` for `Deflated`.
    pub compress_level: u32,
    /// Main workspace directory name under `runfiles_dir` (e.g. `_main`) prepended to main-repo
    /// runfile paths.
    pub workspace_name: String,
    /// Whether `--legacy_external_runfiles` is enabled, stripping leading `external/` prefixes
    /// from external repository runfile short paths.
    pub legacy_external_runfiles: bool,
    /// Directory prefix within the zip archive for runfiles entries, relative to the zip root
    /// (typically `"runfiles"`).
    pub runfiles_dir: String,
    /// Path separator for the target platform (`"/"` on Unix, `"\\"` on Windows), used to
    /// normalize symlink target paths stored in the zip archive.
    pub platform_pathsep: String,
}

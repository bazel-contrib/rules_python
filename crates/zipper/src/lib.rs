//! Library supporting creating deterministic zipapp archives from a manifest.

// Errors must be returned, not panicked; see the `rust-lint` config in .bazelrc.
#![deny(clippy::expect_used, clippy::unwrap_used)]

use std::collections::{HashMap, HashSet};
use std::ffi::OsString;
use std::fs::{self, File, Metadata};
use std::io::{self, BufWriter, Seek, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use anyhow::{Context, Result, bail};
use zip::write::SimpleFileOptions;
use zip::{CompressionMethod, DateTime, System, ZIP64_BYTES_THR, ZipWriter};
use zip_manifest::{RawManifestEntry, SymlinkMode, parse_manifest_line};

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
              `parse_manifest_line` in crates/zip_manifest/src/lib.rs.
  <output>    Path to the output zip file

Options:
  --compression <N>                  Compression level (0 for stored, 1-9 for deflated) [default: 0]
  --workspace-name <NAME>            Name of the workspace [default: \"\"]
  --legacy-external-runfiles <0|1>   Whether to use legacy external runfiles behavior [default: 0]
  --runfiles-dir <DIR>               Name of the runfiles directory [default: runfiles]
  --target-platform-pathsep <SEP>    Path separator for the target platform [default: host separator]
  --link-packed-runfiles-symlinks <0|1>
                                     Store runfiles symlinks to packed files as symlinks to the
                                     packed copy [default: 0]
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
    if legacy_external_runfiles && let Some(rest) = path.strip_prefix("external/") {
        return unix_join(&[runfiles_dir, rest]);
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
            if let Some(&last) = out.last()
                && last != ".."
            {
                out.pop();
                continue;
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

/// Parses a single line of a manifest file and resolves its destination zip path. Returns `None`
/// for blank lines.
///
/// Line formats are documented on [`parse_manifest_line`].
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

    let file = |content_path: &Path, symlink_mode: SymlinkMode| EntryKind::File {
        content_path: content_path.to_path_buf(),
        symlink_mode,
    };
    let rf_path = |runfile_path: &str| {
        get_zip_runfiles_path(
            runfile_path,
            workspace_name,
            legacy_external_runfiles,
            runfiles_dir,
        )
    };

    let entry = match parse_manifest_line(line)?.entry {
        RawManifestEntry::Regular {
            symlink_mode,
            zip_path,
            content_path,
        } => ManifestEntry {
            zip_path: zip_path.to_string(),
            kind: file(content_path, symlink_mode),
            source: EntrySource::Other,
        },
        RawManifestEntry::RfEmpty { runfile_path } => ManifestEntry {
            zip_path: rf_path(runfile_path),
            kind: EntryKind::Empty,
            source: EntrySource::Other,
        },
        RawManifestEntry::RfFile {
            symlink_mode,
            runfile_path,
            content_path,
        } => ManifestEntry {
            zip_path: rf_path(runfile_path),
            kind: file(content_path, symlink_mode),
            source: EntrySource::RunfilesFile,
        },
        RawManifestEntry::RfSymlink {
            symlink_mode,
            runfile_symlink_path,
            content_path,
        } => ManifestEntry {
            zip_path: unix_join(&[runfiles_dir, workspace_name, runfile_symlink_path]),
            kind: file(content_path, symlink_mode),
            source: EntrySource::RunfilesSymlink,
        },
        RawManifestEntry::RfRootSymlink {
            symlink_mode,
            runfile_root_path,
            content_path,
        } => ManifestEntry {
            zip_path: unix_join(&[runfiles_dir, runfile_root_path]),
            kind: file(content_path, symlink_mode),
            source: EntrySource::RunfilesSymlink,
        },
        RawManifestEntry::Symlink {
            runfile_root_path,
            link_to_runfile_root_path,
        } => {
            let zip_path = unix_join(&[runfiles_dir, runfile_root_path]);
            let link_to = unix_join(&[runfiles_dir, link_to_runfile_root_path]);
            let parent = zip_path.rsplit_once('/').map_or("", |(dir, _)| dir);
            let target = relative_path(&link_to, parent);
            ManifestEntry {
                zip_path,
                kind: EntryKind::Symlink { target },
                source: EntrySource::Other,
            }
        }
    };

    Ok(Some(entry))
}

/// Turns runfiles symlinks to packed files into symlinks to the packed copy.
///
/// An `rf-symlink` or `rf-root-symlink` entry whose content is also stored by an `rf-file` entry
/// (e.g. a venv site-packages entry that points into a pip repo) becomes a relative symlink to
/// that `rf-file`'s zip path, instead of a second copy of the content. It keeps the precedence of
/// a regular entry, so a file at the same zip path still wins over it.
fn link_packed_runfiles_symlinks(entries: &mut [ManifestEntry]) {
    let mut packed: HashMap<PathBuf, String> = HashMap::new();
    for entry in entries.iter() {
        if let (EntrySource::RunfilesFile, EntryKind::File { content_path, .. }) =
            (entry.source, &entry.kind)
        {
            packed
                .entry(content_path.clone())
                .or_insert_with(|| normalize_components(&entry.zip_path).join("/"));
        }
    }
    for entry in entries.iter_mut() {
        if entry.source != EntrySource::RunfilesSymlink {
            continue;
        }
        let EntryKind::File { content_path, .. } = &entry.kind else {
            continue;
        };
        let Some(target) = packed.get(content_path) else {
            continue;
        };
        // A link at the target's own path would point to itself.
        if *target == normalize_components(&entry.zip_path).join("/") {
            continue;
        }
        let parent = entry.zip_path.rsplit_once('/').map_or("", |(dir, _)| dir);
        entry.kind = EntryKind::PackedSymlink {
            target: relative_path(target, parent),
        };
    }
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
    if options.link_packed_runfiles_symlinks {
        link_packed_runfiles_symlinks(&mut entries);
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
/// MS-DOS timestamp a zip can represent (1980-01-01 00:00:00) and matches the Python
/// implementation.
const FIXED_TIMESTAMP: DateTime = DateTime::DEFAULT;

fn file_options(compress_level: u32, unix_mode: u32) -> SimpleFileOptions {
    // Use `System::Unix` (matching `tools/zipapp/zipper.py`'s `create_system = 3`) so
    // `zip` preserves `unix_permissions` on Windows too instead of synthesizing DOS modes.
    let options = SimpleFileOptions::default()
        .last_modified_time(FIXED_TIMESTAMP)
        .system(System::Unix)
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
/// symlinks uncompressed, so only the timestamp and system need fixing.
fn symlink_options() -> SimpleFileOptions {
    SimpleFileOptions::default()
        .last_modified_time(FIXED_TIMESTAMP)
        .system(System::Unix)
}

fn write_entry<W: Write + Seek>(
    zf: &mut ZipWriter<W>,
    entry: &ManifestEntry,
    options: &ZipOptions,
    seen: &mut HashSet<String>,
) -> Result<()> {
    // Normalize slashes, otherwise the `seen` logic doesn't work correctly.
    let zip_path = normalize_zip_path(&entry.zip_path);
    let adding = || format!("adding {zip_path}");
    if !seen.insert(zip_path.clone()) {
        // This can occur because symlink entries have precedence over non-symlink entries.
        return Ok(());
    }

    let (content_path, symlink_mode) = match &entry.kind {
        EntryKind::Empty => {
            // Create empty file
            zf.start_file(&zip_path, file_options(options.compress_level, 0o644))
                .with_context(adding)?;
            return Ok(());
        }
        EntryKind::Symlink { target } | EntryKind::PackedSymlink { target } => {
            let target = convert_symlink_target(target, &options.platform_pathsep);
            zf.add_symlink(&zip_path, target, symlink_options())
                .with_context(adding)?;
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
            .with_context(adding)?;
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
    zf.start_file(&zip_path, opts).with_context(adding)?;
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

    // TODO: Use `Path::is_empty()` once it is stable (Rust 1.98).
    if let Some(parent) = options.output_zip.parent()
        && !parent.as_os_str().is_empty()
    {
        fs::create_dir_all(parent)
            .with_context(|| format!("creating directory {}", parent.display()))?;
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
    let mut link_packed_runfiles_symlinks = false;

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
            Long("link-packed-runfiles-symlinks") => {
                link_packed_runfiles_symlinks = parse_bool_flag(
                    "--link-packed-runfiles-symlinks",
                    &parser.value()?.string()?,
                )?;
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
        link_packed_runfiles_symlinks,
    }))
}

/// Parses CLI arguments (excluding `argv[0]` and subcommand name), creates the zip archive, and
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
        Err(msg) => {
            eprintln!("zipper: error: {msg}");
            return ExitCode::FAILURE;
        }
    };
    if let Err(err) = create_zip(&options) {
        eprintln!("zipper: error: {err:#}");
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}

/// Result of parsing the command line.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Cli {
    /// `--help` was requested.
    Help,
    /// Create a zip archive with the given options.
    Run(ZipOptions),
}

/// What a manifest entry stores. See [`parse_manifest_line`] for the manifest line formats.
#[derive(Debug, Clone, PartialEq, Eq)]
enum EntryKind {
    /// An empty regular file (`rf-empty`).
    Empty,
    /// A symlink whose `target` is relative to the parent directory of `zip_path` inside the
    /// zip archive (`symlink`). Takes precedence over other kinds at the same `zip_path`.
    Symlink { target: String },
    /// A runfiles symlink to a file that is also packed, stored as a symlink whose `target` is
    /// relative to the parent directory of `zip_path`. Unlike `Symlink`, it has the precedence of
    /// a regular entry. See [`link_packed_runfiles_symlinks`].
    PackedSymlink { target: String },
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
    /// Which kind of manifest line the entry came from.
    source: EntrySource,
}

/// The kind of manifest line an entry came from, as far as [`link_packed_runfiles_symlinks`]
/// needs to know.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum EntrySource {
    /// `rf-file`.
    RunfilesFile,
    /// `rf-symlink` or `rf-root-symlink`.
    RunfilesSymlink,
    /// Any other line.
    Other,
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
    /// Whether to store `rf-symlink` and `rf-root-symlink` entries whose content is also stored
    /// by an `rf-file` entry as relative symlinks to that entry.
    pub link_packed_runfiles_symlinks: bool,
}

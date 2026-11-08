//! Parser for the `|`-delimited manifest format shared by `zipper` and `zip_main_maker`.

// Errors must be returned, not panicked; see the `rust-lint` config in .bazelrc.
#![deny(clippy::expect_used, clippy::unwrap_used)]

use std::fmt;
use std::path::Path;

mod symlink_modes {
    // keep-sorted start
    pub const INFER: &str = "-1";
    pub const REGULAR: &str = "0";
    pub const SYMLINK: &str = "1";
    // keep-sorted end
}

mod entry_kinds {
    // keep-sorted start
    pub const REGULAR: &str = "regular";
    pub const RF_EMPTY: &str = "rf-empty";
    pub const RF_FILE: &str = "rf-file";
    pub const RF_ROOT_SYMLINK: &str = "rf-root-symlink";
    pub const RF_SYMLINK: &str = "rf-symlink";
    pub const SYMLINK: &str = "symlink";
    // keep-sorted end
}

/// Parses the `is_symlink` field (`"0"`, `"1"`, or `"-1"`) of a manifest line.
pub fn parse_symlink_mode(value: &str) -> Result<SymlinkMode, ManifestParseError> {
    match value {
        symlink_modes::REGULAR => Ok(SymlinkMode::Regular),
        symlink_modes::SYMLINK => Ok(SymlinkMode::Symlink),
        symlink_modes::INFER => Ok(SymlinkMode::Infer),
        _ => Err(ManifestParseError::InvalidSymlinkMode {
            value: value.to_string(),
        }),
    }
}

fn split_two(s: &str) -> Option<(&str, &str)> {
    s.split_once('|').filter(|(_, b)| !b.contains('|'))
}

fn split_three(s: &str) -> Option<(&str, &str, &str)> {
    let (a, rest) = s.split_once('|')?;
    let (b, c) = split_two(rest)?;
    Some((a, b, c))
}

/// Parses a single non-empty manifest line into [`ManifestLine`].
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
pub fn parse_manifest_line(line: &str) -> Result<ManifestLine<'_>, ManifestParseError> {
    let invalid = || ManifestParseError::InvalidFormat {
        line: line.to_string(),
    };
    let Some((kind, rest)) = line.split_once('|') else {
        return Err(invalid());
    };
    let entry = match kind {
        entry_kinds::REGULAR => {
            let (is_symlink, zip_path, content_path) = split_three(rest).ok_or_else(invalid)?;
            RawManifestEntry::Regular {
                symlink_mode: parse_symlink_mode(is_symlink)?,
                zip_path,
                content_path: Path::new(content_path),
            }
        }
        entry_kinds::RF_EMPTY => {
            if rest.contains('|') {
                return Err(invalid());
            }
            RawManifestEntry::RfEmpty { runfile_path: rest }
        }
        entry_kinds::RF_FILE => {
            let (is_symlink, runfile_path, content_path) = split_three(rest).ok_or_else(invalid)?;
            RawManifestEntry::RfFile {
                symlink_mode: parse_symlink_mode(is_symlink)?,
                runfile_path,
                content_path: Path::new(content_path),
            }
        }
        entry_kinds::RF_SYMLINK => {
            let (is_symlink, runfile_symlink_path, content_path) =
                split_three(rest).ok_or_else(invalid)?;
            RawManifestEntry::RfSymlink {
                symlink_mode: parse_symlink_mode(is_symlink)?,
                runfile_symlink_path,
                content_path: Path::new(content_path),
            }
        }
        entry_kinds::RF_ROOT_SYMLINK => {
            let (is_symlink, runfile_root_path, content_path) =
                split_three(rest).ok_or_else(invalid)?;
            RawManifestEntry::RfRootSymlink {
                symlink_mode: parse_symlink_mode(is_symlink)?,
                runfile_root_path,
                content_path: Path::new(content_path),
            }
        }
        entry_kinds::SYMLINK => {
            let (runfile_root_path, link_to_runfile_root_path) =
                split_two(rest).ok_or_else(invalid)?;
            RawManifestEntry::Symlink {
                runfile_root_path,
                link_to_runfile_root_path,
            }
        }
        _ => return Err(invalid()),
    };
    Ok(ManifestLine { rest, entry })
}

/// How an entry's `content_path` should be handled with respect to symlinks, parsed from the
/// `is_symlink` manifest field.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SymlinkMode {
    /// `"0"`: Source is marked as a regular file at analysis time (note: `zipper` still preserves
    /// relative source symlinks when inspecting `content_path` on disk).
    Regular,
    /// `"1"`: Source is a symlink whose target is read via `std::fs::read_link`.
    Symlink,
    /// `"-1"`: Unknown at analysis time (Bazel 7 lacks `File.is_symlink`); treated as `Symlink`
    /// when `content_path` is a dangling symlink (`std::fs::metadata` fails) and `Regular`
    /// otherwise.
    Infer,
}

/// A parsed line from a zipapp manifest.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ManifestLine<'a> {
    /// Raw substring after the leading `<type>|` delimiter (hashed by `zip_main_maker` to capture
    /// the runfiles structure).
    pub rest: &'a str,
    /// Structured representation of the manifest entry.
    pub entry: RawManifestEntry<'a>,
}

/// Structured representation of a single `|`-delimited manifest entry before zip-path resolution.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RawManifestEntry<'a> {
    /// `regular|is_symlink|zip_path|content_path`
    Regular {
        symlink_mode: SymlinkMode,
        /// Destination path inside the zip archive, relative to the zip root.
        zip_path: &'a str,
        /// Source file or symlink path on disk, relative to the current working directory or
        /// absolute.
        content_path: &'a Path,
    },
    /// `rf-empty|runfile_path`
    RfEmpty {
        /// Runfile `short_path` (relative to the main workspace root, using `../<repo>/` or
        /// `external/<repo>/` prefixes for external repositories).
        runfile_path: &'a str,
    },
    /// `rf-file|is_symlink|runfile_path|content_path`
    RfFile {
        symlink_mode: SymlinkMode,
        /// Runfile `short_path` (relative to the main workspace root, using `../<repo>/` or
        /// `external/<repo>/` prefixes for external repositories).
        runfile_path: &'a str,
        /// Source file or symlink path on disk, relative to the current working directory or
        /// absolute.
        content_path: &'a Path,
    },
    /// `rf-symlink|is_symlink|runfile_symlink_path|content_path`
    RfSymlink {
        symlink_mode: SymlinkMode,
        /// Destination symlink path relative to `<runfiles_dir>/<workspace_name>`.
        runfile_symlink_path: &'a str,
        /// Source file or symlink path on disk, relative to the current working directory or
        /// absolute.
        content_path: &'a Path,
    },
    /// `rf-root-symlink|is_symlink|runfile_root_path|content_path`
    RfRootSymlink {
        symlink_mode: SymlinkMode,
        /// Destination symlink path relative to `<runfiles_dir>`.
        runfile_root_path: &'a str,
        /// Source file or symlink path on disk, relative to the current working directory or
        /// absolute.
        content_path: &'a Path,
    },
    /// `symlink|runfile_root_path|link_to_runfile_root_path`
    Symlink {
        /// Destination symlink path relative to `<runfiles_dir>`.
        runfile_root_path: &'a str,
        /// Symlink target path relative to `<runfiles_dir>`.
        link_to_runfile_root_path: &'a str,
    },
}

impl<'a> RawManifestEntry<'a> {
    /// Returns `(symlink_mode, content_path)` (where `content_path` is relative to the current
    /// working directory or absolute) for entry kinds backed by a file or symlink on disk
    /// (`regular`, `rf-file`, `rf-symlink`, `rf-root-symlink`), or `None` for metadata-only
    /// entries (`rf-empty`, `symlink`).
    pub fn content_source(&self) -> Option<(SymlinkMode, &'a Path)> {
        match *self {
            Self::Regular {
                symlink_mode,
                content_path,
                ..
            }
            | Self::RfFile {
                symlink_mode,
                content_path,
                ..
            }
            | Self::RfSymlink {
                symlink_mode,
                content_path,
                ..
            }
            | Self::RfRootSymlink {
                symlink_mode,
                content_path,
                ..
            } => Some((symlink_mode, content_path)),
            Self::RfEmpty { .. } | Self::Symlink { .. } => None,
        }
    }
}

/// Error returned when a manifest line fails syntactic validation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ManifestParseError {
    /// Line has an unknown entry type or wrong number of `|`-delimited fields.
    InvalidFormat { line: String },
    /// The `is_symlink` field is not `"0"`, `"1"`, or `"-1"`.
    InvalidSymlinkMode { value: String },
}

impl fmt::Display for ManifestParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidFormat { line } => {
                write!(f, "unknown entry type or invalid format: {line}")
            }
            Self::InvalidSymlinkMode { value } => {
                write!(
                    f,
                    "invalid is_symlink value (expected {}, {}, or {}): {value}",
                    symlink_modes::REGULAR,
                    symlink_modes::SYMLINK,
                    symlink_modes::INFER,
                )
            }
        }
    }
}

impl std::error::Error for ManifestParseError {}

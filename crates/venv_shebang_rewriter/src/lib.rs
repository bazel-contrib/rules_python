//! Rewrites a `console_script` wrapper's shebang into a batch/shell-Python polyglot.
//!
//! Reads `<in_path>`, replaces its first line with a platform-specific polyglot header for
//! `<target_os>`, writes the result to `<out_path>`, and marks the output executable on Unix.

// Errors must be returned, not panicked; see the `rust-lint` config in .bazelrc.
#![deny(clippy::expect_used, clippy::unwrap_used)]

use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::str::FromStr;

use anyhow::{Context, Result, bail};
use lexopt::prelude::*;

mod flags {
    // keep-sorted start
    pub const HELP: &str = "help";
    pub const HELP_SHORT: char = 'h';
    // keep-sorted end
}

/// Usage text for `--help`. `lexopt` does not generate help, so this is maintained by hand.
const USAGE: &str = "\
Usage: venv_shebang_rewriter <IN_PATH> <OUT_PATH> <TARGET_OS>

Rewrite a console_script wrapper's shebang into a batch/shell-Python polyglot.

Arguments:
  <IN_PATH>     Path to the input script
  <OUT_PATH>    Path to write the rewritten script to
  <TARGET_OS>   Target OS family: 'unix' or 'windows'

Options:
  -h, --help    Print this help";

// Wheel `.data/scripts/*` and `console_scripts` wrappers start with a `#!python` (or `#!pythonw`)
// placeholder shebang. Because Bazel venvs are relocatable across sandboxes and runfiles trees,
// their absolute location is not known at build time, and OS `#!` shebangs cannot resolve an
// interpreter relative to the script's own directory. Instead, we prepend a polyglot header that
// invokes the sibling interpreter in the venv's `bin/` / `Scripts/` directory and is ignored when
// Python subsequently parses the same file.

/// Shell-Python polyglot header for Unix-like platforms:
///
/// ```text
/// #!/bin/sh
/// '''exec' "$(dirname "$0")/python3" "$0" "$@"
/// ' '''
/// ```
///
/// * **As `/bin/sh`**: `''` (an empty single-quoted string) concatenates onto `'exec'` to run
///   `exec`, replacing the shell process with `python3` from the script's directory and forwarding
///   the script path (`"$0"`) and arguments (`"$@"`). Because `exec` does not return, `/bin/sh`
///   never reads line 3 or the Python body below.
/// * **As Python**: Line 1 (`#!/bin/sh`) is a `#` comment, and lines 2–3 (`'''exec' ... \n' '''`)
///   form a single triple-quoted string literal that Python evaluates and discards before running
///   the rest of the file.
pub const UNIX_HEADER: &[u8] =
    b"#!/bin/sh\n'''exec' \"$(dirname \"$0\")/python3\" \"$0\" \"$@\"\n' '''\n";

/// Batch-Python polyglot header for Windows (`python.exe`, CRLF-terminated for `.bat`/`.cmd`):
///
/// * **As `cmd.exe`**: `@` suppresses command echo; `setlocal enabledelayedexpansion` lets
///   `!ERRORLEVEL!` expand *after* Python finishes (whereas `%ERRORLEVEL%` would expand when
///   `cmd.exe` parses the `&`-joined line); `"%~dp0python.exe" -x "%~f0" %*` runs `python.exe` in
///   the script's directory (`%~dp0`) on the script's full path (`%~f0`) with all arguments
///   (`%*`); and `exit /b !ERRORLEVEL!` exits batch execution with Python's exit code before
///   `cmd.exe` reaches the Python body on line 2.
/// * **As Python**: `-x` instructs CPython to skip the first line of the source file, ignoring the
///   batch command and executing the remaining Python code starting at line 2.
pub const WINDOWS_PYTHON_HEADER: &[u8] =
    b"@setlocal enabledelayedexpansion & \"%~dp0python.exe\" -x \"%~f0\" %* & exit /b !ERRORLEVEL!\r\n";

/// Batch-Python polyglot header for Windows GUI scripts (`pythonw.exe`); works identically to
/// [`WINDOWS_PYTHON_HEADER`] when the input script's shebang starts with `#!pythonw`.
pub const WINDOWS_PYTHONW_HEADER: &[u8] =
    b"@setlocal enabledelayedexpansion & \"%~dp0pythonw.exe\" -x \"%~f0\" %* & exit /b !ERRORLEVEL!\r\n";

/// Splits `input` at the first `b'\n'` byte into `(first_line, rest)`.
///
/// `first_line` includes the trailing `b'\n'` if one is present, or the entire slice
/// if `input` contains no newline. `rest` contains all bytes after the first `b'\n'`.
pub fn split_first_line(input: &[u8]) -> (&[u8], &[u8]) {
    if let Some(pos) = input.iter().position(|&b| b == b'\n') {
        (&input[..=pos], &input[pos + 1..])
    } else {
        (input, b"")
    }
}

/// Rewrites the first line of `input` into a batch or shell-Python polyglot header,
/// preserving the remaining bytes verbatim.
pub fn rewrite_shebang_bytes(input: &[u8], target_os: TargetOs) -> Vec<u8> {
    let (first_line, rest) = split_first_line(input);
    let header = match target_os {
        TargetOs::Windows if first_line.starts_with(b"#!pythonw") => WINDOWS_PYTHONW_HEADER,
        TargetOs::Windows => WINDOWS_PYTHON_HEADER,
        TargetOs::Unix => UNIX_HEADER,
    };

    let mut output = Vec::with_capacity(header.len() + rest.len());
    output.extend_from_slice(header);
    output.extend_from_slice(rest);
    output
}

/// Reads `in_path`, rewrites the shebang for `target_os`, writes the result to `out_path`,
/// and sets executable permissions (`mode | 0o111`) on Unix.
///
/// # Errors
///
/// Returns an error if `in_path` cannot be read, or `out_path` cannot be written or
/// have its permissions updated.
pub fn rewrite_shebang(in_path: &Path, out_path: &Path, target_os: TargetOs) -> Result<()> {
    let input = fs::read(in_path).with_context(|| format!("reading {}", in_path.display()))?;
    let output = rewrite_shebang_bytes(&input, target_os);

    fs::write(out_path, &output).with_context(|| format!("writing {}", out_path.display()))?;

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = fs::metadata(out_path)
            .with_context(|| format!("reading metadata of {}", out_path.display()))?
            .permissions();
        perms.set_mode(perms.mode() | 0o111);
        fs::set_permissions(out_path, perms)
            .with_context(|| format!("setting permissions on {}", out_path.display()))?;
    }

    Ok(())
}

/// Parses command-line arguments (excluding `argv[0]` and subcommand name) into [`ParsedArgs`].
///
/// Expects exactly three positionals: `<in_path> <out_path> <target_os>`.
///
/// # Errors
///
/// Returns an error if an unknown flag is given, positional argument count is not 3, or
/// `<target_os>` is not `"unix"` or `"windows"`.
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

    if positional.len() != 3 {
        bail!(
            "expected 3 positional arguments, got {}\n{USAGE}",
            positional.len()
        );
    }
    let mut positional = positional.into_iter();
    let in_path = PathBuf::from(positional.next().context("missing <IN_PATH>")?);
    let out_path = PathBuf::from(positional.next().context("missing <OUT_PATH>")?);
    let target_os = positional.next().context("missing <TARGET_OS>")?;
    let target_os = target_os
        .to_str()
        .with_context(|| format!("target_os is not valid UTF-8: {target_os:?}"))?
        .parse::<TargetOs>()?;

    Ok(ParsedArgs::Options(Options {
        in_path,
        out_path,
        target_os,
    }))
}

/// Parses CLI arguments (excluding `argv[0]` and subcommand name), rewrites the shebang, and
/// returns the process exit code.
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
            eprintln!("venv_shebang_rewriter: error: {err:#}");
            return ExitCode::FAILURE;
        }
    };
    if let Err(err) = rewrite_shebang(&options.in_path, &options.out_path, options.target_os) {
        eprintln!("venv_shebang_rewriter: error: {err:#}");
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

/// Parsed command-line options for `venv_shebang_rewriter`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Options {
    /// Path to the input script, relative to the current working directory or absolute.
    pub in_path: PathBuf,
    /// Path to write the rewritten script to, relative to the current working directory or
    /// absolute.
    pub out_path: PathBuf,
    /// Target OS family selecting the polyglot header.
    pub target_os: TargetOs,
}

/// Target operating system family for generated shebang headers.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TargetOs {
    Unix,
    Windows,
}

impl FromStr for TargetOs {
    type Err = anyhow::Error;

    fn from_str(s: &str) -> Result<Self> {
        match s {
            "unix" => Ok(Self::Unix),
            "windows" => Ok(Self::Windows),
            other => bail!("unsupported target_os '{other}': expected 'unix' or 'windows'"),
        }
    }
}

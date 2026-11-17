//! Library for generating console_script entrypoint Python files from `entry_points.txt`.
//!
//! Parses the `[console_scripts]` section of a wheel's `entry_points.txt`, selects the
//! requested (or guessed) entry point, and renders a Python entrypoint script to `OUT`.
//!
//! The rendered script trims `sys.path[0]` when it points outside the runfiles tree. For
//! Python versions earlier than 3.11 and Bazel versions earlier than 7.0, `sys.path[0]` escapes
//! the runfiles tree (see <https://github.com/bazel-contrib/rules_python/issues/382> and
//! <https://github.com/bazelbuild/bazel/pull/15701>), so a `py_binary` named like the program
//! it wraps (`flake8`, `pylint`, `pytest`, ...) ends up importing its own internals from the
//! Bazel entrypoint script. Dropping the first `sys.path` entry when it lacks `.runfiles` fixes
//! console_scripts under `bazel run`; binaries defined at the root of an external repository
//! (e.g. `@pypi_pylint//`) are unaffected because that path is already inside runfiles.

// Errors must be returned, not panicked; see the `rust-lint` config in .bazelrc.
#![deny(clippy::expect_used, clippy::unwrap_used)]

use std::collections::HashMap;
use std::ffi::OsString;
use std::fs;
use std::path::PathBuf;
use std::process::ExitCode;

use anyhow::{Context, Result, bail};
use lexopt::prelude::*;

mod flags {
    // keep-sorted start
    pub const CONSOLE_SCRIPT: &str = "console-script";
    pub const CONSOLE_SCRIPT_GUESS: &str = "console-script-guess";
    pub const HELP: &str = "help";
    pub const HELP_SHORT: char = 'h';
    pub const SHEBANG: &str = "shebang";
    // keep-sorted end
}

/// Usage text for `--help`. `lexopt` does not generate help, so this is maintained by hand.
const USAGE: &str = "\
Usage: py_console_script_gen [OPTIONS] --console-script-guess <NAME> <ENTRY_POINTS_TXT> <OUT>

Generate a console_script entrypoint Python file from a wheel's entry_points.txt.

Arguments:
  <ENTRY_POINTS_TXT>             The entry_points.txt within the dist-info of a PyPI wheel
  <OUT>                          The output file

Options:
  --console-script <NAME>        The console_script to generate the entry_point template for
  --console-script-guess <NAME>  The string used for guessing the console_script if it is not provided
  --shebang <SHEBANG>            The shebang to use for the entry point python file
  @<FLAGFILE>                    Read newline-delimited arguments from <FLAGFILE>
  -h, --help                     Print this help";

/// Parses the `[console_scripts]` section from an `entry_points.txt` INI string.
///
/// Preserves case-sensitivity of keys (`optionxform = str`).
/// Returns `None` if `[console_scripts]` is absent or empty.
pub fn parse_console_scripts(content: &str) -> Option<HashMap<String, String>> {
    let mut in_console_scripts = false;
    let mut console_scripts: HashMap<String, String> = HashMap::new();

    let lines = content
        .lines()
        .map(|raw_line| (raw_line, raw_line.trim()))
        .filter(|(_, trimmed)| !trimmed.is_empty() && !trimmed.starts_with(['#', ';']));
    for (raw_line, trimmed) in lines {
        if let Some(section) = trimmed.strip_prefix('[').and_then(|s| s.strip_suffix(']')) {
            in_console_scripts = section.trim() == "console_scripts";
            continue;
        }

        if !in_console_scripts || raw_line.starts_with([' ', '\t']) {
            continue;
        }

        if let Some((raw_key, raw_val)) = raw_line.split_once(['=', ':']) {
            let key = raw_key.trim();
            let val = raw_val.trim();
            if !key.is_empty() && !val.is_empty() {
                console_scripts.insert(key.to_owned(), val.to_owned());
            }
        }
    }

    (!console_scripts.is_empty()).then_some(console_scripts)
}

/// Renders the console script template for the given module, imported attribute, entry point, and shebang.
pub fn render_template(shebang: &str, module: &str, attr: &str, entry_point: &str) -> String {
    let shebang_prefix = if shebang.is_empty() {
        String::new()
    } else {
        format!("{shebang}\n")
    };

    format!(
        "{shebang_prefix}import sys

# See @rules_python//crates/py_console_script_gen for explanation
if getattr(sys.flags, \"safe_path\", False):
    # We are running on Python 3.11 and we don't need this workaround
    pass
elif \".runfiles\" not in sys.path[0]:
    sys.path = sys.path[1:]

try:
    from {module} import {attr}
except ImportError:
    entries = \"\\n\".join(sys.path)
    print(\"Printing sys.path entries for easier debugging:\", file=sys.stderr)
    print(f\"sys.path is:\\n{{entries}}\", file=sys.stderr)
    raise

if __name__ == \"__main__\":
    sys.exit({entry_point}())  # pyrefly: ignore[not-callable]
"
    )
}

/// Generates the console script Python file described by `options`.
///
/// # Errors
///
/// Returns `Err` if `entry_points` cannot be read, provides no `[console_scripts]`, does not
/// contain the requested (or guessed) console script, or if `out` cannot be written.
pub fn run(options: &Options) -> Result<()> {
    let content = fs::read_to_string(&options.entry_points)
        .with_context(|| format!("reading {}", options.entry_points.display()))?;

    let console_scripts = parse_console_scripts(&content)
        .context("The package does not provide any console_scripts in its entry_points.txt")?;

    let available = || {
        let mut names: Vec<_> = console_scripts.keys().cloned().collect();
        names.sort_unstable();
        names.join(", ")
    };

    let entry_point = match &options.console_script {
        Some(name) => console_scripts.get(name).with_context(|| {
            format!(
                "The console_script '{name}' was not found, only the following are available: {}",
                available()
            )
        })?,
        None => {
            let guess = &options.console_script_guess;
            console_scripts.get(guess).with_context(|| {
                format!(
                    "Tried to guess that you wanted '{guess}', but could not find it. Please select one of the following console scripts: {}",
                    available()
                )
            })?
        }
    };

    let (module, entry_point_callable) = entry_point.rsplit_once(':').unwrap_or(("", entry_point));
    let attr = entry_point_callable
        .split_once('.')
        .map_or(entry_point_callable, |(first, _)| first);
    // TODO: handle 'extras' in entry_point generation
    // See https://github.com/bazel-contrib/rules_python/issues/1383
    // See https://packaging.python.org/en/latest/specifications/entry-points/

    let rendered = render_template(&options.shebang, module, attr, entry_point_callable);
    fs::write(&options.out, rendered)
        .with_context(|| format!("writing {}", options.out.display()))?;

    Ok(())
}

/// Parses command-line arguments (excluding `argv[0]` and subcommand name) into [`ParsedArgs`].
///
/// # Errors
///
/// Returns `Err` if an `@flagfile` cannot be read, an unknown flag is given, a flag is missing its
/// value, `--console-script-guess` is absent, or there are not exactly two positional arguments.
pub fn parse_args<I, T>(args: I) -> Result<ParsedArgs>
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

    let mut positional: Vec<PathBuf> = Vec::with_capacity(2);
    let mut console_script: Option<String> = None;
    let mut console_script_guess: Option<String> = None;
    let mut shebang = String::new();

    let mut parser = lexopt::Parser::from_args(expanded);
    while let Some(arg) = parser.next()? {
        match arg {
            Short(flags::HELP_SHORT) | Long(flags::HELP) => return Ok(ParsedArgs::Help),
            Long(flags::CONSOLE_SCRIPT) => {
                let val = parser.value()?.string()?;
                console_script = (!val.is_empty()).then_some(val);
            }
            Long(flags::CONSOLE_SCRIPT_GUESS) => {
                console_script_guess = Some(parser.value()?.string()?);
            }
            Long(flags::SHEBANG) => {
                shebang = parser.value()?.string()?;
            }
            Value(val) => positional.push(PathBuf::from(val)),
            _ => bail!("{}", arg.unexpected()),
        }
    }

    let console_script_guess = console_script_guess.with_context(|| {
        format!(
            "missing required argument: --{}",
            flags::CONSOLE_SCRIPT_GUESS
        )
    })?;

    if positional.len() != 2 {
        bail!(
            "expected 2 positional arguments (ENTRY_POINTS_TXT OUT), got {}",
            positional.len()
        );
    }
    let out = positional.remove(1);
    let entry_points = positional.remove(0);

    Ok(ParsedArgs::Options(Options {
        entry_points,
        out,
        console_script,
        console_script_guess,
        shebang,
    }))
}

/// Parses CLI arguments (excluding `argv[0]` and subcommand name), generates the console script,
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
            eprintln!("py_console_script_gen: error: {err:#}");
            return ExitCode::FAILURE;
        }
    };
    if let Err(err) = run(&options) {
        eprintln!("py_console_script_gen: error: {err:#}");
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

/// Parsed command-line options for `py_console_script_gen`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Options {
    /// Path to the `entry_points.txt` file to parse, relative to the current working directory or
    /// absolute.
    pub entry_points: PathBuf,
    /// Path of the Python entrypoint script to write, relative to the current working directory
    /// or absolute.
    pub out: PathBuf,
    /// Explicitly requested console script name; `None` when absent or empty.
    pub console_script: Option<String>,
    /// Name to look up when `console_script` is `None`.
    pub console_script_guess: String,
    /// Shebang line to prepend to the script; empty for none.
    pub shebang: String,
}

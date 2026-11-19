//! Library for generating console_script entrypoint Python files from `entry_points.txt`.
//!
//! Parses the `[console_scripts]` section of a wheel's `entry_points.txt`, selects the
//! requested (or guessed) entry point, and expands a Python entrypoint template to `OUT`.
//!
//! The default template (`//python/private:console_script_template.txt`) trims `sys.path[0]`
//! when it points outside the runfiles tree. For Python versions earlier than 3.11 and Bazel
//! versions earlier than 7.0, `sys.path[0]` escapes the runfiles tree (see
//! <https://github.com/bazel-contrib/rules_python/issues/382> and
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

use anyhow::{Context, Result, anyhow, bail};
use configparser::ini::Ini;
use lexopt::prelude::*;

mod flags {
    // keep-sorted start
    pub const CONSOLE_SCRIPT: &str = "console-script";
    pub const CONSOLE_SCRIPT_GUESS: &str = "console-script-guess";
    pub const HELP: &str = "help";
    pub const HELP_SHORT: char = 'h';
    pub const SHEBANG: &str = "shebang";
    pub const TEMPLATE: &str = "template";
    // keep-sorted end
}

mod placeholders {
    // keep-sorted start
    pub const ATTR: &str = "%attr%";
    pub const ENTRY_POINT: &str = "%entry_point%";
    pub const MODULE: &str = "%module%";
    pub const SHEBANG: &str = "%shebang%";
    // keep-sorted end
}

/// Usage text for `--help`. `lexopt` does not generate help, so this is maintained by hand.
const USAGE: &str = "\
Usage: py_console_script_gen [OPTIONS] --template <PATH> --console-script-guess <NAME> <ENTRY_POINTS_TXT> <OUT>

Generate a console_script entrypoint Python file from a wheel's entry_points.txt.

Arguments:
  <ENTRY_POINTS_TXT>             The entry_points.txt within the dist-info of a PyPI wheel
  <OUT>                          The output file

Options:
  --template <PATH>              Path to the Python entrypoint template file
  --console-script <NAME>        The console_script to generate the entry_point template for
  --console-script-guess <NAME>  The string used for guessing the console_script if it is not provided
  --shebang <SHEBANG>            The shebang to use for the entry point python file
  @<FLAGFILE>                    Read newline-delimited arguments from <FLAGFILE>
  -h, --help                     Print this help";

/// Parses the `[console_scripts]` section from an `entry_points.txt` INI string.
///
/// Matches Python's `configparser.ConfigParser` with `optionxform = str` (case-sensitive keys,
/// `=` and `:` delimiters, `#` and `;` full-line comments, no inline comment stripping, and
/// indented continuation lines). Returns `Ok(None)` if `[console_scripts]` is absent or has no
/// non-empty entries.
///
/// # Errors
///
/// Returns `Err` if `content` contains malformed INI syntax (such as an unclosed `[section`
/// header or an empty option key).
pub fn parse_console_scripts(content: &str) -> Result<Option<HashMap<String, String>>> {
    let mut defaults = Ini::new_cs().defaults();
    defaults.enable_inline_comments = false;
    defaults.multiline = true;
    let mut ini = Ini::new_from_defaults(defaults);
    let mut sections = ini
        .read(content.to_owned())
        .map_err(|err| anyhow!("parsing entry_points.txt: {err}"))?;
    let Some(section) = sections.remove("console_scripts") else {
        return Ok(None);
    };
    let console_scripts: HashMap<String, String> = section
        .into_iter()
        .filter_map(|(key, val)| val.filter(|v| !v.is_empty()).map(|v| (key, v)))
        .collect();
    Ok((!console_scripts.is_empty()).then_some(console_scripts))
}

/// Substitutes `%shebang%`, `%module%`, `%attr%`, and `%entry_point%` placeholders in `template`.
pub fn render_template(
    template: &str,
    shebang: &str,
    module: &str,
    attr: &str,
    entry_point: &str,
) -> String {
    let shebang_prefix = if shebang.is_empty() {
        String::new()
    } else {
        format!("{shebang}\n")
    };

    template
        .replace(placeholders::SHEBANG, &shebang_prefix)
        .replace(placeholders::MODULE, module)
        .replace(placeholders::ATTR, attr)
        .replace(placeholders::ENTRY_POINT, entry_point)
}

/// Generates the console script Python file described by `options`.
///
/// # Errors
///
/// Returns `Err` if `entry_points` or `template` cannot be read, `entry_points` contains invalid
/// INI syntax or provides no `[console_scripts]`, the requested (or guessed) console script is
/// missing, or `out` cannot be written.
pub fn run(options: &Options) -> Result<()> {
    let content = fs::read_to_string(&options.entry_points)
        .with_context(|| format!("reading {}", options.entry_points.display()))?;

    let console_scripts = parse_console_scripts(&content)?
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

    let template = fs::read_to_string(&options.template)
        .with_context(|| format!("reading template {}", options.template.display()))?;
    let rendered = render_template(
        &template,
        &options.shebang,
        module,
        attr,
        entry_point_callable,
    );
    fs::write(&options.out, rendered)
        .with_context(|| format!("writing {}", options.out.display()))?;

    Ok(())
}

/// Parses command-line arguments (excluding `argv[0]` and subcommand name) into [`ParsedArgs`].
///
/// # Errors
///
/// Returns `Err` if an `@flagfile` cannot be read, an unknown flag is given, a flag is missing its
/// value, `--template` or `--console-script-guess` is absent, or there are not exactly two
/// positional arguments.
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
    let mut template: Option<PathBuf> = None;
    let mut console_script: Option<String> = None;
    let mut console_script_guess: Option<String> = None;
    let mut shebang = String::new();

    let mut parser = lexopt::Parser::from_args(expanded);
    while let Some(arg) = parser.next()? {
        match arg {
            Short(flags::HELP_SHORT) | Long(flags::HELP) => return Ok(ParsedArgs::Help),
            Long(flags::TEMPLATE) => {
                template = Some(PathBuf::from(parser.value()?));
            }
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

    let template =
        template.with_context(|| format!("missing required argument: --{}", flags::TEMPLATE))?;
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
        template,
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
    /// Path to the Python entrypoint template file, relative to the current working directory or
    /// absolute.
    pub template: PathBuf,
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

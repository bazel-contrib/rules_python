//! Library for generating console_script entrypoint Python files from `entry_points.txt`.

use std::collections::HashMap;
use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

/// Parsed command-line options for `py_console_script_gen`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Options {
    pub entry_points: PathBuf,
    pub out: PathBuf,
    pub console_script: Option<String>,
    pub console_script_guess: String,
    pub shebang: String,
}

/// Expands `@flagfile` arguments into `OsString` values via `argfile`.
pub fn expand_args<I, T>(args: I) -> Result<Vec<OsString>, String>
where
    I: IntoIterator<Item = T>,
    T: Into<OsString>,
{
    let raw_args: Vec<OsString> = args.into_iter().map(Into::into).collect();
    if raw_args.iter().any(|arg| arg == "@") {
        return Err("flagfile path after '@' must not be empty".to_string());
    }
    argfile::expand_args_from(
        raw_args.into_iter(),
        argfile::parse_fromfile,
        argfile::PREFIX,
    )
    .map_err(|e| format!("failed to read flagfile: {e}"))
}

/// Parses command-line arguments (excluding `argv[0]`) into `Options`.
pub fn parse_args<I, T>(args: I) -> Result<Options, String>
where
    I: IntoIterator<Item = T>,
    T: Into<OsString>,
{
    use lexopt::prelude::*;

    let expanded = expand_args(args)?;
    let mut positional: Vec<PathBuf> = Vec::with_capacity(2);
    let mut console_script: Option<String> = None;
    let mut console_script_guess: Option<String> = None;
    let mut shebang = String::new();

    let mut parser = lexopt::Parser::from_args(expanded);
    while let Some(arg) = parser.next().map_err(|e| e.to_string())? {
        match arg {
            Short('h') | Long("help") => {
                return Err(
                    "Usage: py_console_script_gen [--console-script <str>] --console-script-guess <str> [--shebang <str>] <ENTRY_POINTS_TXT> <OUT>"
                        .to_string(),
                );
            }
            Long("console-script") => {
                let val = parser
                    .value()
                    .map_err(|e| e.to_string())?
                    .string()
                    .map_err(|e| e.to_string())?;
                console_script = (!val.is_empty()).then_some(val);
            }
            Long("console-script-guess") => {
                let val = parser
                    .value()
                    .map_err(|e| e.to_string())?
                    .string()
                    .map_err(|e| e.to_string())?;
                console_script_guess = Some(val);
            }
            Long("shebang") => {
                shebang = parser
                    .value()
                    .map_err(|e| e.to_string())?
                    .string()
                    .map_err(|e| e.to_string())?;
            }
            Value(val) => positional.push(PathBuf::from(val)),
            _ => return Err(arg.unexpected().to_string()),
        }
    }

    let console_script_guess = console_script_guess.ok_or_else(|| {
        "the following arguments are required: --console-script-guess".to_string()
    })?;

    if positional.len() != 2 {
        return Err(format!(
            "expected 2 positional arguments (ENTRY_POINTS_TXT OUT), got {}",
            positional.len()
        ));
    }

    let mut pos_iter = positional.into_iter();
    let entry_points = pos_iter.next().unwrap();
    let out = pos_iter.next().unwrap();

    Ok(Options {
        entry_points,
        out,
        console_script,
        console_script_guess,
        shebang,
    })
}

/// Runs the generator using parsed `Options`.
pub fn run_with_options(options: &Options) -> Result<(), String> {
    run(
        &options.entry_points,
        &options.out,
        options.console_script.as_deref(),
        &options.console_script_guess,
        &options.shebang,
    )
}

/// Parses CLI arguments (excluding `argv[0]` and subcommand name), generates the console script,
/// and returns the process exit code.
pub fn run_cli<I, T>(args: I) -> ExitCode
where
    I: IntoIterator<Item = T>,
    T: Into<OsString>,
{
    let options = match parse_args(args) {
        Ok(opts) => opts,
        Err(msg) => {
            eprintln!("py_console_script_gen: error: {msg}");
            return ExitCode::FAILURE;
        }
    };
    if let Err(err) = run_with_options(&options) {
        eprintln!("py_console_script_gen: error: {err}");
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}

/// Parses the `[console_scripts]` section from an `entry_points.txt` INI string.
///
/// Preserves case-sensitivity of keys (`optionxform = str`).
/// Returns `None` if `[console_scripts]` is absent or empty.
pub fn parse_console_scripts(content: &str) -> Option<HashMap<String, String>> {
    let mut in_console_scripts = false;
    let mut console_scripts: HashMap<String, String> = HashMap::new();

    for raw_line in content.lines() {
        let trimmed = raw_line.trim();
        if trimmed.is_empty() || trimmed.starts_with(['#', ';']) {
            continue;
        }

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

# See @rules_python//python/private:py_console_script_gen.py for explanation
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

/// Generates a console script Python file from `entry_points.txt` according to the given parameters.
pub fn run(
    entry_points: &Path,
    out: &Path,
    console_script: Option<&str>,
    console_script_guess: &str,
    shebang: &str,
) -> Result<(), String> {
    let content = fs::read_to_string(entry_points)
        .map_err(|e| format!("failed to read {}: {e}", entry_points.display()))?;

    let console_scripts = parse_console_scripts(&content).ok_or_else(|| {
        "The package does not provide any console_scripts in its entry_points.txt".to_string()
    })?;

    let (script_name, is_explicit) = match console_script.filter(|s| !s.is_empty()) {
        Some(explicit) => (explicit, true),
        None => (console_script_guess, false),
    };

    let Some(entry_point) = console_scripts.get(script_name) else {
        let mut available: Vec<_> = console_scripts.keys().cloned().collect();
        available.sort_unstable();
        let available_list = available.join(", ");
        return if is_explicit {
            Err(format!(
                "The console_script '{script_name}' was not found, only the following are available: {available_list}"
            ))
        } else {
            Err(format!(
                "Tried to guess that you wanted '{script_name}', but could not find it. Please select one of the following console scripts: {available_list}"
            ))
        };
    };

    let (module, entry_point_callable) = entry_point.rsplit_once(':').unwrap_or(("", entry_point));
    let attr = entry_point_callable
        .split_once('.')
        .map_or(entry_point_callable, |(first, _)| first);

    let rendered = render_template(shebang, module, attr, entry_point_callable);

    if let Some(parent) = out.parent()
        && !parent.as_os_str().is_empty()
    {
        fs::create_dir_all(parent)
            .map_err(|e| format!("failed to create directory {}: {e}", parent.display()))?;
    }

    fs::write(out, rendered).map_err(|e| format!("failed to write {}: {e}", out.display()))?;

    Ok(())
}

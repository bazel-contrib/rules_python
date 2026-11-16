//! Static validator checking that a `py_test` main module runs test code.
//!
//! Mirrors `python/private/py_test_main_validator.py`: parses the Python main
//! module and fails if the module defines top-level test classes or functions
//! (`def`, `async def`, `class`) while every top-level statement is inert.

// Errors must be returned, not panicked; see the `rust-lint` config in .bazelrc.
#![deny(clippy::expect_used, clippy::unwrap_used)]

use std::borrow::Cow;
use std::ffi::OsString;
use std::fmt;
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::LazyLock;

use anyhow::{Context, Result, bail};
use lexopt::prelude::*;
use ruff_python_ast::visitor::{Visitor, walk_expr};
use ruff_python_ast::{ExceptHandler, Expr, ModModule, Stmt};

mod flags {
    // keep-sorted start
    pub const HELP: &str = "help";
    pub const HELP_SHORT: char = 'h';
    pub const LABEL: &str = "label";
    pub const OUTPUT: &str = "output";
    pub const SRC: &str = "src";
    pub const SRC_NAME: &str = "src_name";
    // keep-sorted end
}

/// Usage text for `--help`. `lexopt` does not generate help, so this is maintained by hand.
const USAGE: &str = "\
Usage: py_test_main_validator [OPTIONS] --src <PATH> --output <PATH>

Check that a py_test main module runs test code, not just defines it.

Options:
  --src <PATH>         Path to the main .py source file to analyze
  --src_name <NAME>    Human-friendly name of the source file, used in error messages
  --label <LABEL>      The py_test target label, used in error messages
  --output <PATH>      Path to the validation marker file to write on success
  @<FLAGFILE>          Read newline-delimited arguments from <FLAGFILE>
  -h, --help           Print this help";

/// Error returned when a Python source file cannot be decoded or parsed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SyntaxError {
    pub message: String,
}

impl SyntaxError {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl fmt::Display for SyntaxError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl std::error::Error for SyntaxError {}

/// Formats the validation failure message matching `_format_error` in
/// `python/private/py_test_main_validator.py`.
pub fn format_error(label: &str, src_name: &str) -> String {
    let target = if label.is_empty() { src_name } else { label };
    format!(
        "py_test target {target} will not run any tests.\n\
         \n\
         The main module '{src_name}' only contains inert top-level statements \
         (class/function definitions, imports, assignments). Running it does \
         nothing, so the test silently passes without executing any test \
         code.\n\
         \n\
         py_test runs the main module directly; it does not automatically \
         invoke a test runner such as unittest or pytest. Add code that runs \
         your tests, for example:\n\
         \n\
         \x20   if __name__ == \"__main__\":\n\
         \x20       unittest.main()\n\
         \n\
         or use a main module that invokes a runner (e.g. pytest.main()).\n\
         \n\
         This check can be disabled by setting \
         --@rules_python//python/config_settings:validate_test_main=disabled."
    )
}

fn is_blank_or_comment_line(line: &[u8]) -> bool {
    let first_non_ws = line
        .iter()
        .copied()
        .find(|&b| !matches!(b, b' ' | b'\t' | b'\x0c'));
    matches!(first_non_ws, None | Some(b'#'))
}

/// PEP 263 coding-cookie pattern; compiled once and shared across calls.
static COOKIE_RE: LazyLock<std::result::Result<regex::bytes::Regex, regex::Error>> =
    LazyLock::new(|| {
        regex::bytes::Regex::new(r"(?-u)^[ \t\x0c]*#.*?coding[:=][ \t]*([-_.a-zA-Z0-9]+)")
    });

/// Returns the encoding named by a PEP 263 coding cookie on `line`, if any.
fn cookie_encoding<'a>(re: &regex::bytes::Regex, line: &'a [u8]) -> Option<&'a str> {
    let line = line.strip_suffix(b"\r").unwrap_or(line);
    let caps = re.captures(line)?;
    std::str::from_utf8(caps.get(1)?.as_bytes()).ok()
}

fn extract_pep263_encoding(body: &[u8]) -> std::result::Result<Option<&str>, SyntaxError> {
    let re = COOKIE_RE
        .as_ref()
        .map_err(|e| SyntaxError::new(format!("invalid PEP 263 regex: {e}")))?;

    let mut lines = body.split(|&b| b == b'\n');
    let Some(line1) = lines.next() else {
        return Ok(None);
    };
    if let Some(enc) = cookie_encoding(re, line1) {
        return Ok(Some(enc));
    }
    if !is_blank_or_comment_line(line1) {
        return Ok(None);
    }
    Ok(lines.next().and_then(|line2| cookie_encoding(re, line2)))
}

fn decode_python_source(source: &[u8]) -> std::result::Result<Cow<'_, str>, SyntaxError> {
    if source.contains(&0) {
        return Err(SyntaxError::new("source code cannot contain null bytes"));
    }

    let (has_bom, body) = match source.strip_prefix(b"\xef\xbb\xbf") {
        Some(rest) => (true, rest),
        None => (false, source),
    };

    let Some(raw_enc) = extract_pep263_encoding(body)? else {
        return std::str::from_utf8(body)
            .map(Cow::Borrowed)
            .map_err(|_| SyntaxError::new("invalid utf-8 encoding"));
    };

    let normalized = raw_enc.to_ascii_lowercase().replace('_', "-");
    let is_utf8 = matches!(normalized.as_str(), "utf-8" | "utf8" | "utf-8-sig");
    if has_bom && !is_utf8 {
        return Err(SyntaxError::new("encoding problem: utf-8 with BOM"));
    }

    if is_utf8 {
        return std::str::from_utf8(body)
            .map(Cow::Borrowed)
            .map_err(|_| SyntaxError::new("invalid utf-8 encoding"));
    }

    match normalized.as_str() {
        "ascii" | "us-ascii" | "646" | "ansi-x3.4-1968" => {
            if !body.is_ascii() {
                return Err(SyntaxError::new("'ascii' codec can't decode byte"));
            }
            std::str::from_utf8(body)
                .map(Cow::Borrowed)
                .map_err(|_| SyntaxError::new("invalid ascii encoding"))
        }
        "latin-1" | "latin1" | "iso-8859-1" | "iso8859-1" | "iso-latin-1" | "latin" | "l1" => {
            if body.is_ascii()
                && let Ok(ascii_str) = std::str::from_utf8(body)
            {
                Ok(Cow::Borrowed(ascii_str))
            } else {
                Ok(Cow::Owned(body.iter().map(|&b| char::from(b)).collect()))
            }
        }
        _ => Err(SyntaxError::new(format!("unknown encoding: {raw_enc}"))),
    }
}

#[derive(Default)]
struct ActiveExprFinder {
    found: bool,
}

impl<'a> Visitor<'a> for ActiveExprFinder {
    fn visit_expr(&mut self, expr: &'a Expr) {
        if self.found {
            return;
        }
        if matches!(
            expr,
            Expr::Call(_) | Expr::Await(_) | Expr::Yield(_) | Expr::YieldFrom(_)
        ) {
            self.found = true;
            return;
        }
        walk_expr(self, expr);
    }
}

fn expr_runs_code(expr: &Expr) -> bool {
    let mut finder = ActiveExprFinder::default();
    finder.visit_expr(expr);
    finder.found
}

fn all_inert(stmts: &[Stmt]) -> bool {
    stmts.iter().all(is_inert_statement)
}

/// Returns `true` if `stmt` does not run any test code.
pub fn is_inert_statement(stmt: &Stmt) -> bool {
    match stmt {
        Stmt::FunctionDef(_)
        | Stmt::ClassDef(_)
        | Stmt::Import(_)
        | Stmt::ImportFrom(_)
        | Stmt::Global(_)
        | Stmt::Pass(_)
        | Stmt::TypeAlias(_) => true,
        Stmt::Assign(node) => !expr_runs_code(&node.value),
        Stmt::AugAssign(node) => !expr_runs_code(&node.value),
        Stmt::AnnAssign(node) => node.value.as_deref().is_none_or(|v| !expr_runs_code(v)),
        Stmt::Assert(node) => {
            !expr_runs_code(&node.test) && node.msg.as_deref().is_none_or(|m| !expr_runs_code(m))
        }
        Stmt::Expr(node) => !expr_runs_code(&node.value),
        Stmt::If(node) => {
            !expr_runs_code(&node.test)
                && all_inert(&node.body)
                && node.elif_else_clauses.iter().all(|clause| {
                    clause.test.as_ref().is_none_or(|t| !expr_runs_code(t))
                        && all_inert(&clause.body)
                })
        }
        Stmt::Try(node) => {
            all_inert(&node.body)
                && all_inert(&node.orelse)
                && all_inert(&node.finalbody)
                && node
                    .handlers
                    .iter()
                    .all(|ExceptHandler::ExceptHandler(h)| all_inert(&h.body))
        }
        _ => false,
    }
}

/// Returns `true` if the module body has at least one active statement.
pub fn module_runs_something(body: &[Stmt]) -> bool {
    body.iter().any(|stmt| !is_inert_statement(stmt))
}

/// Returns `true` if the module defines any top-level class or function.
pub fn defines_test_code(body: &[Stmt]) -> bool {
    body.iter()
        .any(|stmt| matches!(stmt, Stmt::FunctionDef(_) | Stmt::ClassDef(_)))
}

/// Returns `true` if the module appears able to run tests (or defines no test code).
pub fn module_runs_tests(body: &[Stmt]) -> bool {
    module_runs_something(body) || !defines_test_code(body)
}

fn parse_python_module(source: &str) -> std::result::Result<ModModule, SyntaxError> {
    if source.contains('\0') {
        return Err(SyntaxError::new("source code cannot contain null bytes"));
    }
    ruff_python_parser::parse_module(source)
        .map(ruff_python_parser::Parsed::into_syntax)
        .map_err(|e| SyntaxError::new(e.to_string()))
}

/// Parses `source` bytes and returns whether the module runs tests (or defines no test code).
pub fn module_runs_tests_bytes(source: &[u8]) -> std::result::Result<bool, SyntaxError> {
    let text = decode_python_source(source)?;
    module_runs_tests_str(&text)
}

/// Parses `source` string and returns whether the module runs tests (or defines no test code).
pub fn module_runs_tests_str(source: &str) -> std::result::Result<bool, SyntaxError> {
    let module = parse_python_module(source)?;
    Ok(module_runs_tests(&module.body))
}

/// Parses `source` string and returns whether the module has at least one active top-level
/// statement.
pub fn module_runs_something_str(source: &str) -> std::result::Result<bool, SyntaxError> {
    let module = parse_python_module(source)?;
    Ok(module_runs_something(&module.body))
}

/// Parsed command-line options for `py_test_main_validator`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Options {
    /// Path to the main `.py` source file to analyze.
    pub src: PathBuf,
    /// Human-friendly name of the source file, used in error messages (defaults to `src`).
    pub src_name: String,
    /// The `py_test` target label, used in error messages.
    pub label: String,
    /// Path to the validation marker file to write on success.
    pub output: PathBuf,
}

/// Result of parsing the command line.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Cli {
    /// `--help` was requested.
    Help,
    /// Validate the main module with the given options.
    Run(Options),
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

    let mut src: Option<PathBuf> = None;
    let mut src_name = String::new();
    let mut label = String::new();
    let mut output: Option<PathBuf> = None;

    let mut parser = lexopt::Parser::from_args(expanded);
    while let Some(arg) = parser.next()? {
        match arg {
            Short(flags::HELP_SHORT) | Long(flags::HELP) => return Ok(Cli::Help),
            Long(flags::SRC) => {
                src = Some(PathBuf::from(parser.value()?));
            }
            Long(flags::SRC_NAME) => {
                src_name = parser.value()?.string()?;
            }
            Long(flags::LABEL) => {
                label = parser.value()?.string()?;
            }
            Long(flags::OUTPUT) => {
                output = Some(PathBuf::from(parser.value()?));
            }
            _ => bail!("{}", arg.unexpected()),
        }
    }

    let src = src.with_context(|| format!("missing required argument: --{}", flags::SRC))?;
    let output =
        output.with_context(|| format!("missing required argument: --{}", flags::OUTPUT))?;

    if src_name.is_empty() {
        src_name = src.display().to_string();
    }

    Ok(Cli::Run(Options {
        src,
        src_name,
        label,
        output,
    }))
}

fn write_empty_output(output: &Path) -> Result<()> {
    fs::write(output, "").with_context(|| format!("writing {}", output.display()))
}

/// Runs validation according to `options`, writing any diagnostic messages to `stderr`.
///
/// # Errors
///
/// Returns `Err` if the source cannot be read, the output marker cannot be written, or
/// `stderr` cannot be written to.
pub fn validate_test_main(options: &Options, stderr: &mut dyn Write) -> Result<ExitCode> {
    let source =
        fs::read(&options.src).with_context(|| format!("reading {}", options.src.display()))?;
    let src_name = &options.src_name;

    match module_runs_tests_bytes(&source) {
        Err(err) => {
            writeln!(
                stderr,
                "WARNING: py_test main validator could not parse {src_name}: {err}"
            )?;
            write_empty_output(&options.output)?;
            Ok(ExitCode::SUCCESS)
        }
        Ok(false) => {
            writeln!(stderr, "{}", format_error(&options.label, src_name))?;
            Ok(ExitCode::FAILURE)
        }
        Ok(true) => {
            write_empty_output(&options.output)?;
            Ok(ExitCode::SUCCESS)
        }
    }
}

/// Top-level CLI runner taking raw arguments (excluding `argv[0]` and subcommand name) and
/// writing diagnostics to `stderr`.
pub fn run<I, T>(args: I, stderr: &mut dyn Write) -> ExitCode
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
            let _ = writeln!(stderr, "py_test_main_validator: error: {err:#}");
            return ExitCode::FAILURE;
        }
    };

    match validate_test_main(&options, stderr) {
        Ok(code) => code,
        Err(err) => {
            let _ = writeln!(stderr, "py_test_main_validator: error: {err:#}");
            ExitCode::FAILURE
        }
    }
}

/// Parses CLI arguments (excluding `argv[0]` and subcommand name), validates the test main
/// module, and returns the process exit code.
pub fn run_cli<I, T>(args: I) -> ExitCode
where
    I: IntoIterator<Item = T>,
    T: Into<OsString>,
{
    run(args, &mut io::stderr())
}

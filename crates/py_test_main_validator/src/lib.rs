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

/// PEP 263 coding-cookie pattern; compiled once and shared across calls.
static COOKIE_RE: LazyLock<regex::bytes::Regex> = LazyLock::new(|| {
    #[expect(
        clippy::expect_used,
        reason = "static PEP 263 regex literal is infallible"
    )]
    regex::bytes::Regex::new(r"(?-u)^[ \t\x0c]*#.*?coding[:=][ \t]*([-_.a-zA-Z0-9]+)")
        .expect("PEP 263 regex literal should compile")
});

/// Formats the validation failure message for an inert `py_test` main module.
pub fn format_error(label: &str, src_name: &str) -> String {
    let target = if label.is_empty() { src_name } else { label };
    format!(
        r#"py_test target {target} will not run any tests.

The main module '{src_name}' only contains inert top-level statements
(class/function definitions, imports, assignments). Running it does
nothing, so the test silently passes without executing any test code.

py_test runs the main module directly; it does not automatically invoke
a test runner such as unittest or pytest. Add code that runs your tests,
for example:

    if __name__ == "__main__":
        unittest.main()

or use a main module that invokes a runner (e.g. pytest.main()).

This check can be disabled by setting
--@rules_python//python/config_settings:validate_test_main=disabled."#
    )
}

fn is_blank_or_comment_line(line: &[u8]) -> bool {
    line.trim_ascii_start().first().is_none_or(|&b| b == b'#')
}

/// Returns the encoding named by a PEP 263 coding cookie on `line`, if any.
fn cookie_encoding(line: &[u8]) -> Option<&[u8]> {
    COOKIE_RE.captures(line)?.get(1).map(|m| m.as_bytes())
}

fn extract_pep263_encoding(body: &[u8]) -> Option<&[u8]> {
    let mut lines = body.split(|&b| b == b'\n');
    let line1 = lines.next()?;
    if let Some(enc) = cookie_encoding(line1) {
        return Some(enc);
    }
    // PEP 263 (`tokenize.detect_encoding`) only inspects line 2 when line 1 is blank or a
    // comment (such as a `#!` shebang); code on line 1 disables line-2 cookie detection.
    if !is_blank_or_comment_line(line1) {
        return None;
    }
    lines.next().and_then(cookie_encoding)
}

fn is_utf8_encoding_name(normalized: &[u8]) -> bool {
    normalized == b"utf-8" || normalized == b"utf8" || normalized.starts_with(b"utf-8-")
}

fn is_ascii_encoding_name(normalized: &[u8]) -> bool {
    matches!(
        normalized,
        b"ascii" | b"us-ascii" | b"646" | b"ansi-x3.4-1968"
    )
}

fn is_latin1_encoding_name(normalized: &[u8]) -> bool {
    matches!(
        normalized,
        b"latin-1" | b"latin1" | b"iso-8859-1" | b"iso8859-1" | b"iso-latin-1" | b"latin" | b"l1"
    ) || normalized.starts_with(b"latin-1-")
        || normalized.starts_with(b"iso-8859-1-")
        || normalized.starts_with(b"iso-latin-1-")
}

/// Decodes `source` bytes into UTF-8 text following PEP 263 (`ruff_python_parser` only accepts
/// `&str` and does not decode non-UTF-8 byte sources or reject NUL bytes inside strings).
fn decode_python_source(source: &[u8]) -> std::result::Result<Cow<'_, str>, SyntaxError> {
    if source.contains(&0) {
        return Err(SyntaxError::new("source code cannot contain null bytes"));
    }

    let (has_bom, body) = match source.strip_prefix(b"\xef\xbb\xbf") {
        Some(rest) => (true, rest),
        None => (false, source),
    };

    let Some(raw_enc) = extract_pep263_encoding(body) else {
        return std::str::from_utf8(body)
            .map(Cow::Borrowed)
            .map_err(|_| SyntaxError::new("invalid utf-8 encoding"));
    };

    // Match CPython `get_normal_name` (Parser/tokenizer/helpers.c), including Emacs `-unix`,
    // `-dos`, and `-mac` suffixes on `utf-8-*` and `(latin-1|iso-8859-1|iso-latin-1)-*`.
    let normalized: Vec<u8> = raw_enc
        .iter()
        .map(|&b| {
            if b == b'_' {
                b'-'
            } else {
                b.to_ascii_lowercase()
            }
        })
        .collect();
    let is_utf8 = is_utf8_encoding_name(&normalized);
    if has_bom && !is_utf8 {
        return Err(SyntaxError::new("encoding problem: utf-8 with BOM"));
    }

    if is_utf8 {
        std::str::from_utf8(body)
            .map(Cow::Borrowed)
            .map_err(|_| SyntaxError::new("invalid utf-8 encoding"))
    } else if is_ascii_encoding_name(&normalized) {
        if !body.is_ascii() {
            return Err(SyntaxError::new("'ascii' codec can't decode byte"));
        }
        std::str::from_utf8(body)
            .map(Cow::Borrowed)
            .map_err(|_| SyntaxError::new("invalid ascii encoding"))
    } else if is_latin1_encoding_name(&normalized) {
        if body.is_ascii()
            && let Ok(ascii_str) = std::str::from_utf8(body)
        {
            Ok(Cow::Borrowed(ascii_str))
        } else {
            Ok(Cow::Owned(body.iter().map(|&b| char::from(b)).collect()))
        }
    } else {
        Err(SyntaxError::new(format!(
            "unknown encoding: {}",
            String::from_utf8_lossy(raw_enc)
        )))
    }
}

/// Returns `true` if evaluating `expr` does not invoke a call, `await`, or `yield`.
///
/// Walks `expr` as written without modeling execution (for example, a call inside an uninvoked
/// `lambda` body still counts as active); erring toward "runs code" avoids false positives on
/// valid tests.
fn is_inert_expr(expr: &Expr) -> bool {
    let mut finder = ActiveExprFinder::default();
    finder.visit_expr(expr);
    !finder.found
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
        Stmt::Assign(node) => is_inert_expr(&node.value),
        Stmt::AugAssign(node) => is_inert_expr(&node.value),
        Stmt::AnnAssign(node) => node.value.as_deref().is_none_or(is_inert_expr),
        Stmt::Assert(node) => {
            is_inert_expr(&node.test) && node.msg.as_deref().is_none_or(is_inert_expr)
        }
        Stmt::Expr(node) => is_inert_expr(&node.value),
        // Inspect `if` and `try` (`try`/`except*`) blocks recursively so inert guards such as
        // `if TYPE_CHECKING:` or `try: import foo except ImportError:` do not bypass the check.
        Stmt::If(node) => {
            is_inert_expr(&node.test)
                && all_inert(&node.body)
                && node.elif_else_clauses.iter().all(|clause| {
                    clause.test.as_ref().is_none_or(is_inert_expr) && all_inert(&clause.body)
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
///
/// A module that defines no classes or functions at all (for example, one that only imports other
/// modules) is always allowed: it is not the "defined tests but forgot to run them" pitfall this
/// check targets, and it may legitimately rely on import side effects.
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
///
/// # Errors
///
/// Returns [`SyntaxError`] if `source` contains null bytes, cannot be decoded according to UTF-8
/// or its PEP 263 coding cookie, or is not valid Python syntax.
pub fn module_runs_tests_bytes(source: &[u8]) -> std::result::Result<bool, SyntaxError> {
    let text = decode_python_source(source)?;
    module_runs_tests_str(&text)
}

/// Parses `source` string and returns whether the module runs tests (or defines no test code).
///
/// # Errors
///
/// Returns [`SyntaxError`] if `source` contains null bytes or is not valid Python syntax.
pub fn module_runs_tests_str(source: &str) -> std::result::Result<bool, SyntaxError> {
    let module = parse_python_module(source)?;
    Ok(module_runs_tests(&module.body))
}

/// Parses `source` string and returns whether the module has at least one active top-level
/// statement.
///
/// # Errors
///
/// Returns [`SyntaxError`] if `source` contains null bytes or is not valid Python syntax.
pub fn module_runs_something_str(source: &str) -> std::result::Result<bool, SyntaxError> {
    let module = parse_python_module(source)?;
    Ok(module_runs_something(&module.body))
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
            // Syntax/encoding errors are surfaced by compilation or execution actions; warn and
            // write the declared output marker so we do not emit duplicate build failures.
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
            // Validation actions must produce their declared outputs on success.
            write_empty_output(&options.output)?;
            Ok(ExitCode::SUCCESS)
        }
    }
}

/// Parses command-line arguments (excluding `argv[0]` and subcommand name) into [`ParsedArgs`].
///
/// # Errors
///
/// Returns `Err` if an `@flagfile` cannot be read, an unknown flag is given, a flag value is
/// missing or not valid UTF-8, or `--src` or `--output` is omitted.
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

    let mut src: Option<PathBuf> = None;
    let mut src_name = String::new();
    let mut label = String::new();
    let mut output: Option<PathBuf> = None;

    let mut parser = lexopt::Parser::from_args(expanded);
    while let Some(arg) = parser.next()? {
        match arg {
            Short(flags::HELP_SHORT) | Long(flags::HELP) => return Ok(ParsedArgs::Help),
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

    Ok(ParsedArgs::Options(Options {
        src,
        src_name,
        label,
        output,
    }))
}

/// Top-level CLI runner taking raw arguments (excluding `argv[0]` and subcommand name) and
/// writing diagnostics to `stderr`.
pub fn run<I, T>(args: I, stderr: &mut dyn Write) -> ExitCode
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

/// Result of parsing command-line arguments.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ParsedArgs {
    /// `--help` was requested.
    Help,
    /// Parsed options for validating the main module.
    Options(Options),
}

/// Parsed command-line options for `py_test_main_validator`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Options {
    /// Path to the main `.py` source file to analyze, relative to the current working directory
    /// or absolute.
    pub src: PathBuf,
    /// Human-friendly name of the source file, used in error messages (defaults to `src`).
    pub src_name: String,
    /// The `py_test` target label, used in error messages.
    pub label: String,
    /// Path to the validation marker file to write on success, relative to the current working
    /// directory or absolute.
    pub output: PathBuf,
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
        // `await`/`yield` cannot appear directly at module top level, but are included for
        // completeness when walking nested expressions.
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

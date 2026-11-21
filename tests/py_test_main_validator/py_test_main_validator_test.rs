use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::ExitCode;
use std::sync::atomic::{AtomicUsize, Ordering};

use py_test_main_validator_lib::{
    Options, ParsedArgs, format_error, module_runs_something_str, module_runs_tests_bytes,
    module_runs_tests_str, parse_args, run, run_cli, validate_test_main,
};

static COUNTER: AtomicUsize = AtomicUsize::new(0);

/// Parses `args` and unwraps the `ParsedArgs::Options` variant.
fn parse_options<const N: usize>(args: [String; N]) -> Options {
    match parse_args(args).expect("arguments should parse successfully") {
        ParsedArgs::Options(options) => options,
        ParsedArgs::Help => panic!("expected ParsedArgs::Options, got ParsedArgs::Help"),
    }
}

fn runs_tests(source: &str) -> bool {
    module_runs_tests_str(&dedent(source)).expect("source should be valid Python syntax")
}

fn dedent(s: &str) -> String {
    let lines: Vec<&str> = s.lines().collect();
    let min_indent = lines
        .iter()
        .filter(|line| !line.trim().is_empty())
        .map(|line| line.len() - line.trim_start_matches(' ').len())
        .min()
        .unwrap_or(0);

    let mut out = String::new();
    for (idx, line) in lines.iter().enumerate() {
        if idx > 0 {
            out.push('\n');
        }
        if line.len() >= min_indent {
            out.push_str(&line[min_indent..]);
        } else {
            out.push_str(line.trim());
        }
    }
    out
}

// ============================================================================
// Ported tests from `tests/validate_test_main/validate_test_main_test.py`
// ============================================================================

#[test]
fn test_only_definitions_is_rejected() {
    assert!(!runs_tests(
        r#"
        import unittest

        class MyTest(unittest.TestCase):
            def test_foo(self):
                self.assertTrue(True)
        "#
    ));
}

#[test]
fn test_definitions_with_assignments_is_rejected() {
    assert!(!runs_tests(
        r#"
        import unittest

        CONSTANT = 5

        class MyTest(unittest.TestCase):
            def test_foo(self):
                pass

        def helper(): pass
        "#
    ));
}

#[test]
fn test_global_statement_with_definition_is_rejected() {
    assert!(!runs_tests(
        r#"
        global x

        class MyTest:
            def test_foo(self):
                pass
        "#
    ));
}

#[test]
fn test_assert_statement_with_definition_is_rejected() {
    assert!(!runs_tests(
        r#"
        assert True

        class MyTest:
            def test_foo(self):
                pass
        "#
    ));
}

#[test]
fn test_assert_statement_with_active_expression_runs_tests() {
    assert!(runs_tests(
        r#"
        import unittest

        class MyTest(unittest.TestCase):
            def test_foo(self):
                pass

        assert unittest.main()
        "#
    ));
}

#[test]
fn test_type_alias_with_definition_is_rejected() {
    assert!(!runs_tests(
        r#"
        type Alias = int

        class MyTest:
            def test_foo(self):
                pass
        "#
    ));
}

#[test]
fn test_type_checking_block_with_definition_is_rejected() {
    assert!(!runs_tests(
        r#"
        from typing import TYPE_CHECKING
        import unittest

        if TYPE_CHECKING:
            from typing import Any

        class MyTest(unittest.TestCase):
            def test_foo(self):
                pass
        "#
    ));
}

#[test]
fn test_try_except_import_error_with_definition_is_rejected() {
    assert!(!runs_tests(
        r#"
        try:
            import foo
        except ImportError:
            foo = None

        import unittest

        class MyTest(unittest.TestCase):
            def test_foo(self):
                pass
        "#
    ));
}

#[test]
fn test_definitions_with_active_assignment_runs_tests() {
    assert!(runs_tests(
        r#"
        import unittest

        class MyTest(unittest.TestCase):
            def test_foo(self):
                pass

        exit_code = unittest.main()
        "#
    ));
}

#[test]
fn test_definitions_with_active_expression_runs_tests() {
    assert!(runs_tests(
        r#"
        import sys
        import unittest

        class MyTest(unittest.TestCase):
            def test_foo(self):
                pass

        sys.exit(unittest.main())
        "#
    ));
}

#[test]
fn test_if_block_invoking_runner_runs_tests() {
    assert!(runs_tests(
        r#"
        import sys
        import unittest

        class MyTest(unittest.TestCase):
            def test_foo(self):
                pass

        if "--run" in sys.argv:
            unittest.main()
        "#
    ));
}

#[test]
fn test_import_only_module_is_allowed() {
    assert!(runs_tests(
        r#"
        import my_tests
        from my_pkg.tests import suite
        "#
    ));
}

#[test]
fn test_imports_and_assignments_without_definitions_is_allowed() {
    assert!(runs_tests(
        r#"
        import my_tests

        CONSTANT = 5
        "#
    ));
}

#[test]
fn test_empty_module_is_allowed() {
    assert!(runs_tests(""));
}

#[test]
fn test_docstring_only_is_allowed() {
    assert!(runs_tests(r#""""A module docstring.""""#));
}

#[test]
fn test_if_name_main_guard_runs_tests() {
    assert!(runs_tests(
        r#"
        import unittest

        class MyTest(unittest.TestCase):
            def test_foo(self):
                pass

        if __name__ == "__main__":
            unittest.main()
        "#
    ));
}

#[test]
fn test_bare_call_runs_tests() {
    assert!(runs_tests(
        r#"
        import pytest
        pytest.main()
        "#
    ));
}

#[test]
fn test_top_level_loop_runs_tests() {
    assert!(runs_tests(
        r#"
        def f(): pass

        for _ in range(1):
            f()
        "#
    ));
}

// ============================================================================
// Additional Edge Cases & Adversarial Parity Tests
// ============================================================================

#[test]
fn test_async_def_and_decorators_are_inert_definitions() {
    assert!(!runs_tests(
        r#"
        @decorator_call(1, 2)
        @another.decorator
        async def test_async():
            await something()

        @class_decorator()
        class TestSuite(BaseCall()):
            def test_one(self):
                pass
        "#
    ));
}

#[test]
fn test_type_annotations_with_calls_vs_values_with_calls() {
    // In `AnnAssign`, `node.annotation` is NOT checked by `py_test_main_validator.py`;
    // only `node.value` is checked!
    assert!(!runs_tests(
        r#"
        def test_something():
            pass

        x: Foo() = 1
        y: Bar(baz())
        "#
    ));

    // When `node.value` has a call, it IS active!
    assert!(runs_tests(
        r#"
        def test_something():
            pass

        x: int = foo()
        "#
    ));
}

#[test]
fn test_aug_assign_inert_vs_active() {
    assert!(!runs_tests(
        r#"
        def test_something():
            pass

        x = 1
        x += 2
        "#
    ));

    assert!(runs_tests(
        r#"
        def test_something():
            pass

        x = 1
        x += run_tests()
        "#
    ));
}

#[test]
fn test_fstrings_with_and_without_calls() {
    assert!(!runs_tests(
        r#"
        def test_something():
            pass

        name = "world"
        msg = f"hello {name!r:>10} {{not_a_call()}} {(1 + 2)}"
        "#
    ));

    assert!(runs_tests(
        r#"
        def test_something():
            pass

        msg = f"result: {run_tests()}"
        "#
    ));

    // Call inside nested f-string format spec `{x:{width()}}`.
    assert!(runs_tests(
        r#"
        def test_something():
            pass

        msg = f"result: {1:{get_width()}}"
        "#
    ));
}

#[test]
fn test_multiline_strings_and_comments_do_not_trigger_calls() {
    assert!(!runs_tests(
        r#"
        # unittest.main() in a comment
        """
        if __name__ == "__main__":
            unittest.main()
        """
        def test_foo():
            pass
        "#
    ));
}

#[test]
fn test_semicolons_on_single_line() {
    assert!(!runs_tests(
        r#"
        import unittest; x = 1; y = 2;
        def test_foo(): pass
        "#
    ));

    assert!(runs_tests(
        r#"
        import unittest; def_like = 1
        def test_foo(): pass
        x = 1; unittest.main()
        "#
    ));
}

#[test]
fn test_nested_if_elif_else_and_try_except_else_finally() {
    // Entirely inert nested if/elif/else and try/except/else/finally.
    assert!(!runs_tests(
        r#"
        def test_foo():
            pass

        if COND_A:
            try:
                import a
            except (ImportError, AttributeError) as err:
                a = None
            else:
                b = 1
            finally:
                c = 2
        elif COND_B:
            pass
        else:
            x = [1, 2, (3, 4), {5: 6}]
        "#
    ));

    // Active call in `elif` condition.
    assert!(runs_tests(
        r#"
        def test_foo():
            pass

        if False:
            pass
        elif check_should_run():
            pass
        "#
    ));

    // Active call in `finally` block.
    assert!(runs_tests(
        r#"
        def test_foo():
            pass

        try:
            pass
        finally:
            unittest.main()
        "#
    ));

    // `try / except*` (PEP 654).
    assert!(!runs_tests(
        r#"
        def test_foo():
            pass

        try:
            x = 1
        except* ValueError as eg:
            x = 2
        "#
    ));
}

#[test]
fn test_comprehensions_lambdas_and_callable_chains() {
    // Comprehension without calls is inert.
    assert!(!runs_tests(
        r#"
        def test_foo():
            pass

        items = [x + 1 for x in (1, 2, 3) if (x > 0)]
        fn = lambda x, y=1: (x + y)
        "#
    ));

    // Comprehension with a call is active.
    assert!(runs_tests(
        r#"
        def test_foo():
            pass

        items = [run(x) for x in [1, 2]]
        "#
    ));

    // Lambda body with a call is active (matches `ast.walk`).
    assert!(runs_tests(
        r#"
        def test_foo():
            pass

        fn = lambda: unittest.main()
        "#
    ));

    // Calling a parenthesized expression or subscript `(get_runner)() / runners[0]()`.
    assert!(runs_tests(
        r#"
        def test_foo():
            pass

        (unittest.main)()
        "#
    ));
    assert!(runs_tests(
        r#"
        def test_foo():
            pass

        runners[0]()
        "#
    ));
}

#[test]
fn test_other_active_statements() {
    for snippet in [
        "def test_f(): pass\nwhile False:\n    pass\n",
        "def test_f(): pass\nwith ctx:\n    pass\n",
        "def test_f(): pass\nraise SystemExit\n",
        "def test_f(): pass\ndel x\n",
        "def test_f(): pass\nmatch x:\n    case 1:\n        pass\n",
        "def test_f(): pass\nassert True, get_message()\n",
    ] {
        assert!(
            module_runs_tests_str(snippet).unwrap(),
            "expected snippet to be considered active:\n{}",
            snippet
        );
        assert!(
            module_runs_something_str(snippet).unwrap(),
            "expected module_runs_something to be true:\n{}",
            snippet
        );
    }
}

#[test]
fn test_syntax_errors_detected() {
    for broken in [
        "def broken(",
        "if :\n    pass",
        "class :\n    pass",
        "x = 'unterminated string",
        "x = (1 + 2",
        "x = [1, 2)",
        "    unexpected_indent = 1",
        "if True:\n",
        "elif True:\n    pass",
        "else:\n    pass",
        "except Exception:\n    pass",
        "try:\n    pass\n",
        "@decorator_without_def\nx = 1\n",
        "1 = 2",
        "foo() = 1",
        "x = 1 +",
        "f'single } brace'",
        "f'empty {} expr'",
    ] {
        assert!(
            module_runs_tests_str(broken).is_err(),
            "expected SyntaxError for broken input:\n{}",
            broken
        );
    }

    // Null bytes and invalid UTF-8 bytes must also return SyntaxError.
    assert!(module_runs_tests_bytes(b"def test_f(): pass\n\x00").is_err());
    assert!(module_runs_tests_bytes(b"\xff\xfeinvalid utf8").is_err());
}

// ============================================================================
// CLI & End-to-End File I/O Tests
// ============================================================================

#[test]
fn test_cli_passing_test_main_writes_empty_output() {
    let dir = TempDir::new("pass");
    let src = dir.path.join("test_ok.py");
    let out = dir.path.join("out.txt");

    fs::write(
        &src,
        "import unittest\nclass T(unittest.TestCase):\n    pass\nif __name__ == '__main__':\n    unittest.main()\n",
    )
    .unwrap();

    let mut stderr = Vec::new();
    let code = run(
        [
            "--src",
            src.to_str().unwrap(),
            "--src_name",
            "pkg/test_ok.py",
            "--label",
            "//pkg:test_ok",
            "--output",
            out.to_str().unwrap(),
        ],
        &mut stderr,
    );

    assert_eq!(code, ExitCode::SUCCESS);
    assert!(stderr.is_empty());
    assert_eq!(fs::read_to_string(&out).unwrap(), "");
}

#[test]
fn test_cli_inert_test_main_fails_with_exact_error_and_no_output() {
    let dir = TempDir::new("fail");
    let src = dir.path.join("test_inert.py");
    let out = dir.path.join("out.txt");

    fs::write(
        &src,
        "import unittest\nclass T(unittest.TestCase):\n    def test_a(self):\n        pass\n",
    )
    .unwrap();

    let mut stderr = Vec::new();
    let code = run(
        [
            format!("--src={}", src.display()),
            "--src_name=pkg/test_inert.py".to_string(),
            "--label=//pkg:test_inert".to_string(),
            format!("--output={}", out.display()),
        ],
        &mut stderr,
    );

    assert_eq!(code, ExitCode::FAILURE);
    assert!(!out.exists(), "output file must not be written on failure");
    let stderr_str = String::from_utf8(stderr).unwrap();
    let expected = format!(
        "{}\n",
        format_error("//pkg:test_inert", "pkg/test_inert.py")
    );
    assert_eq!(stderr_str, expected);
}

#[test]
fn test_cli_syntax_error_warns_writes_output_and_exits_zero() {
    let dir = TempDir::new("syntax_err");
    let src = dir.path.join("broken.py");
    let out = dir.path.join("out.txt");

    fs::write(&src, "def broken(\n").unwrap();

    let mut stderr = Vec::new();
    let opts = Options {
        src: src.clone(),
        src_name: "pkg/broken.py".to_string(),
        label: "//pkg:broken".to_string(),
        output: out.clone(),
    };

    let code = validate_test_main(&opts, &mut stderr).unwrap();
    assert_eq!(code, ExitCode::SUCCESS);
    assert_eq!(fs::read_to_string(&out).unwrap(), "");
    let stderr_str = String::from_utf8(stderr).unwrap();
    assert!(
        stderr_str.starts_with("WARNING: py_test main validator could not parse pkg/broken.py: "),
        "unexpected stderr: {}",
        stderr_str
    );
}

#[test]
fn test_cli_flagfile_and_label_fallback() {
    let dir = TempDir::new("flagfile");
    let src = dir.path.join("inert.py");
    let out = dir.path.join("out.txt");
    let flagfile = dir.path.join("args.params");

    fs::write(&src, "def test_nothing():\n    pass\n").unwrap();
    fs::write(
        &flagfile,
        format!(
            "--src\n{}\n--src_name\npkg/inert.py\n--output\n{}\n",
            src.display(),
            out.display()
        ),
    )
    .unwrap();

    let parsed = parse_options([format!("@{}", flagfile.display())]);
    assert_eq!(parsed.src, src);
    assert_eq!(parsed.src_name, "pkg/inert.py");
    assert_eq!(parsed.label, "");
    assert_eq!(parsed.output, out);

    let mut stderr = Vec::new();
    let code = validate_test_main(&parsed, &mut stderr).expect("validation should succeed");
    assert_eq!(code, ExitCode::FAILURE);
    let stderr_str = String::from_utf8(stderr).unwrap();
    // When `--label` is empty, `target` falls back to `src_name`.
    assert!(stderr_str.starts_with("py_test target pkg/inert.py will not run any tests.\n"));
}

#[test]
fn test_utf8_bom_no_trailing_newline_slices_imports_and_await_yield() {
    // UTF-8 BOM with inert test definition -> rejected.
    assert!(!module_runs_tests_bytes(b"\xef\xbb\xbfdef test_f():\n    pass").unwrap());

    // Relative and multiline imports, dict/tuple comprehensions, and slices without calls -> inert.
    assert!(!runs_tests(
        r#"
        from . import a
        from ..sub.pkg import (
            b as b_alias,
            c,
        )

        def test_foo():
            pass

        s = items[::2] + items[1::] + items[:3:]
        d = {k: v for k, v in pairs if k is not None and v not in excluded}
        "#
    ));

    // `await`, `yield`, and `yield from` in top-level expressions count as active code.
    assert!(runs_tests("def test_foo(): pass\nx = await runner()\n"));
    assert!(runs_tests("def test_foo(): pass\nyield 1\n"));
    assert!(runs_tests("def test_foo(): pass\nyield from gen\n"));
}

#[test]
fn test_nested_tuple_and_list_unpacking_targets() {
    // Nested unpacking inside `def` must not raise a false SyntaxError and must be rejected as
    // inert.
    assert_eq!(
        module_runs_tests_str(
            "def test_for_unpack():\n    for i, (a, b) in enumerate(items):\n        pass\n"
        ),
        Ok(false)
    );
    assert_eq!(
        module_runs_tests_str("def test_tuple_unpack():\n    a, (b, c) = (1, (2, 3))\n"),
        Ok(false)
    );
    assert_eq!(
        module_runs_tests_str("def test_list_unpack():\n    [a, b], c = ([1, 2], 3)\n"),
        Ok(false)
    );

    // Inert top-level nested unpacking with literal RHS must also be rejected as inert.
    assert!(!runs_tests(
        r#"
        a, (b, c) = (1, (2, 3))
        [d, (e, *f)], g = ([4, (5, 6, 7)], 8)

        def test_foo():
            for i, (x, [y, z]) in enumerate(items):
                pass
        "#
    ));

    // Active top-level nested unpacking calling a function is accepted.
    assert!(runs_tests(
        r#"
        def test_foo():
            pass

        a, (b, c) = get_pair()
        "#
    ));

    // CLI exits 1 on inert test file with nested unpacking inside `def`.
    let dir = TempDir::new("nested_unpack_cli");
    let src = dir.path.join("test_unpack.py");
    let out = dir.path.join("out.txt");
    fs::write(
        &src,
        "def test_unpack():\n    for i, (a, b) in enumerate(items):\n        a, (b, c) = (1, (2, 3))\n        [x, y], z = ([1, 2], 3)\n",
    )
    .unwrap();
    let mut stderr = Vec::new();
    let code = run(
        [
            format!("--src={}", src.display()),
            "--src_name=pkg/test_unpack.py".to_string(),
            "--label=@@//pkg:test_unpack".to_string(),
            format!("--output={}", out.display()),
        ],
        &mut stderr,
    );
    assert_eq!(code, ExitCode::FAILURE);
    assert!(!out.exists());
    assert!(
        String::from_utf8_lossy(&stderr)
            .starts_with("py_test target @@//pkg:test_unpack will not run any tests.\n")
    );

    // CLI exits 0 on active top-level nested unpacking with `@//`-prefixed `--label=...`.
    fs::write(
        &src,
        "def test_unpack():\n    pass\na, (b, c) = get_pair()\n",
    )
    .unwrap();
    stderr.clear();
    let code = run(
        [
            format!("--src={}", src.display()),
            "--src_name=pkg/test_unpack.py".to_string(),
            "--label=@//pkg:test_unpack".to_string(),
            format!("--output={}", out.display()),
        ],
        &mut stderr,
    );
    assert_eq!(code, ExitCode::SUCCESS);
    assert!(out.exists());
}

#[test]
fn test_fstring_backslash_before_braces() {
    // Raw f-string and escaped-backslash f-string inside `def` must not skip `{` and must be
    // rejected as inert.
    assert!(!runs_tests(
        r#"
        def test_win_path():
            p = rf"{root}\{name}"
        "#
    ));
    assert!(!runs_tests(
        r#"
        def test_escaped_slash():
            p = f"\\{name}"
        "#
    ));
    assert!(!runs_tests(
        r#"
        def test_unicode_escape():
            p = f"\N{SNOWMAN}{name}"
        "#
    ));

    // Top-level raw f-string with backslash before active interpolation `{run_tests()}` is
    // accepted as active.
    assert!(runs_tests(
        r#"
        def test_win_path():
            pass
        p = rf"C:\{run_tests()}"
        "#
    ));
}

#[test]
fn test_pep263_coding_cookies_and_run_cli_exit_codes() {
    // Line 1 & line 2 Latin-1 coding cookies with non-UTF-8 bytes (including CRLF blank line 1).
    assert_eq!(
        module_runs_tests_bytes(b"# -*- coding: latin-1 -*-\ndef test_f():\n    s = '\xe9'\n"),
        Ok(false)
    );
    assert_eq!(
        module_runs_tests_bytes(
            b"\r\n# -*- coding: latin-1 -*-\r\ndef test_f():\r\n    s = '\xe9'\r\n"
        ),
        Ok(false)
    );
    assert_eq!(
        module_runs_tests_bytes(
            b"#!/usr/bin/env python3\n# vim: set fileencoding=iso-8859-1 :\ndef test_f():\n    s = '\xe9'\nunittest.main()\n"
        ),
        Ok(true)
    );

    // Emacs `-unix`, `-dos`, and `-mac` PEP 263 suffixes match CPython `get_normal_name`.
    assert_eq!(
        module_runs_tests_bytes(b"# -*- coding: utf-8-unix -*-\ndef test_f():\n    pass\n"),
        Ok(false)
    );
    assert_eq!(
        module_runs_tests_bytes(
            b"# -*- coding: iso-latin-1-unix -*-\ndef test_f():\n    s = '\xe9'\n"
        ),
        Ok(false)
    );
    assert_eq!(
        module_runs_tests_bytes(
            b"# -*- coding: latin-1-dos -*-\r\ndef test_f():\r\n    s = '\xe9'\r\nunittest.main()\r\n"
        ),
        Ok(true)
    );

    // ASCII coding cookie rejects non-ASCII bytes.
    assert!(module_runs_tests_bytes(b"# coding: ascii\nx = '\xe9'\n").is_err());

    // UTF-8 BOM conflicting with non-UTF-8 coding cookie is a SyntaxError.
    assert!(module_runs_tests_bytes(b"\xef\xbb\xbf# coding: latin-1\nx = 1\n").is_err());

    // Unknown encoding cookie is a SyntaxError.
    assert!(module_runs_tests_bytes(b"# coding: made_up_encoding_xyz\nx = 1\n").is_err());

    // Invalid CLI arguments fail with a usage error on stderr.
    let mut stderr = Vec::new();
    assert_eq!(run::<_, &str>([], &mut stderr), ExitCode::FAILURE);
    let stderr_str = String::from_utf8(stderr).unwrap();
    assert!(
        stderr_str.contains("missing required argument: --src"),
        "unexpected stderr: {stderr_str}"
    );
    assert_eq!(run_cli(["--unknown-flag"]), ExitCode::FAILURE);
    assert!(parse_args(["--unknown-flag"]).is_err());
    assert!(
        parse_args(["-s", "x"]).is_err(),
        "short flags are not accepted"
    );
}

#[test]
fn test_parse_args_help_and_src_name_fallback() {
    assert_eq!(parse_args(["--help"]).unwrap(), ParsedArgs::Help);
    assert_eq!(parse_args(["-h"]).unwrap(), ParsedArgs::Help);

    // `--src_name` defaults to `--src` when omitted, matching the Python tool.
    let parsed = parse_options([
        "--src=pkg/test_a.py".to_string(),
        "--output=out.txt".to_string(),
    ]);
    assert_eq!(parsed.src, PathBuf::from("pkg/test_a.py"));
    assert_eq!(parsed.src_name, "pkg/test_a.py");
    assert_eq!(parsed.label, "");
    assert_eq!(parsed.output, PathBuf::from("out.txt"));
}

struct TempDir {
    path: PathBuf,
}

impl TempDir {
    fn new(prefix: &str) -> Self {
        let id = COUNTER.fetch_add(1, Ordering::SeqCst);
        let base = env::var_os("TEST_TMPDIR")
            .map(PathBuf::from)
            .unwrap_or_else(env::temp_dir);
        let path = base.join(format!(
            "py_test_main_validator_{}_{}_{}",
            prefix,
            std::process::id(),
            id
        ));
        let _ = fs::remove_dir_all(&path);
        fs::create_dir_all(&path).unwrap();
        Self { path }
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

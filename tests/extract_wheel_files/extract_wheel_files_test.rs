use std::collections::HashSet;
use std::env;
use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::atomic::{AtomicUsize, Ordering};

use extract_wheel_files_lib::{
    Options, ParsedArgs, compile_pattern, extract_files, get_files, get_record, open_wheel_archive,
    parse_args, parse_record, run, run_cli,
};
use zip::write::SimpleFileOptions;
use zip::{CompressionMethod, ZipWriter};

static TEST_COUNTER: AtomicUsize = AtomicUsize::new(0);

const EXAMPLE_WHEEL_REL_PATH: &str =
    "examples/wheel/example_minimal_package-0.0.1-py3-none-any.whl";

/// Parses `args` and unwraps the [`ParsedArgs::Options`] options.
fn parse_options<const N: usize>(args: [&str; N]) -> Options {
    match parse_args(args).expect("arguments should parse") {
        ParsedArgs::Options(opts) => opts,
        ParsedArgs::Help => panic!("expected ParsedArgs::Options, got ParsedArgs::Help"),
    }
}

fn read_wheel_record(whl_path: &Path) -> anyhow::Result<Vec<String>> {
    let mut archive = open_wheel_archive(whl_path)?;
    get_record(&mut archive, whl_path)
}

fn extract_wheel_entries<I, S>(whl_path: &Path, files: I, outdir: &Path) -> anyhow::Result<()>
where
    I: IntoIterator<Item = S>,
    S: AsRef<str>,
{
    let mut archive = open_wheel_archive(whl_path)?;
    extract_files(&mut archive, whl_path, files, outdir)
}

/// Helper to build a valid ZIP archive on disk using the `zip` crate.
fn write_test_zip(
    zip_path: &Path,
    entries: &[(&str, &[u8], CompressionMethod)],
    comment: Option<&str>,
) {
    let file = File::create(zip_path).unwrap();
    let mut writer = ZipWriter::new(file);
    if let Some(c) = comment {
        writer.set_comment(c).unwrap();
    }
    for &(name, data, method) in entries {
        let options = SimpleFileOptions::default()
            .compression_method(method)
            .unix_permissions(0o644);
        writer.start_file(name, options).unwrap();
        writer.write_all(data).unwrap();
    }
    writer.finish().unwrap();
}

/// Recursively collects all regular files under `dir` as relative POSIX paths.
fn collect_extracted_files(dir: &Path) -> HashSet<String> {
    let mut out = HashSet::new();
    let mut stack = vec![dir.to_path_buf()];
    while let Some(curr) = stack.pop() {
        if let Ok(entries) = fs::read_dir(&curr) {
            for entry in entries.flatten() {
                let p = entry.path();
                if p.is_dir() {
                    stack.push(p);
                } else if p.is_file() {
                    let rel = p
                        .strip_prefix(dir)
                        .unwrap()
                        .components()
                        .map(|c| c.as_os_str().to_string_lossy().into_owned())
                        .collect::<Vec<_>>()
                        .join("/");
                    out.insert(rel);
                }
            }
        }
    }
    out
}

fn create_synthetic_minimal_wheel(
    whl_path: &Path,
    method: CompressionMethod,
    comment: Option<&str>,
) {
    let record_content = r#""examples/wheel/lib/data,with,commas.txt",sha256=abc,12
examples/wheel/lib/data.txt,sha256=def,8
examples/wheel/lib/module_with_data.py,sha256=ghi,20
examples/wheel/lib/module_with_type_annotations.py,sha256=jkl,25
examples/wheel/lib/module_with_type_annotations.pyi,sha256=mno,26
examples/wheel/lib/simple_module.py,sha256=pqr,15
examples/wheel/main.py,sha256=stu,18
example_minimal_package-0.0.1.dist-info/WHEEL,sha256=vwx,30
example_minimal_package-0.0.1.dist-info/METADATA,sha256=yz0,40
example_minimal_package-0.0.1.dist-info/RECORD,,
"#;
    let entries: &[(&str, &[u8], CompressionMethod)] = &[
        (
            "examples/wheel/lib/data,with,commas.txt",
            b"comma,data\n",
            method,
        ),
        ("examples/wheel/lib/data.txt", b"data\n", method),
        (
            "examples/wheel/lib/module_with_data.py",
            b"def foo(): pass\n",
            method,
        ),
        (
            "examples/wheel/lib/module_with_type_annotations.py",
            b"x: int = 1\n",
            method,
        ),
        (
            "examples/wheel/lib/module_with_type_annotations.pyi",
            b"x: int\n",
            method,
        ),
        ("examples/wheel/lib/simple_module.py", b"y = 2\n", method),
        (
            "examples/wheel/main.py",
            b"if __name__ == '__main__': pass\n",
            method,
        ),
        (
            "example_minimal_package-0.0.1.dist-info/WHEEL",
            b"Wheel-Version: 1.0\n",
            method,
        ),
        (
            "example_minimal_package-0.0.1.dist-info/METADATA",
            b"Name: example_minimal_package\nVersion: 0.0.1\n",
            method,
        ),
        (
            "example_minimal_package-0.0.1.dist-info/RECORD",
            record_content.as_bytes(),
            method,
        ),
    ];
    write_test_zip(whl_path, entries, comment);
}

#[test]
fn test_parse_record_csv_edge_cases() {
    let csv_bytes = concat!(
        r#""pkg/file,with,commas.txt",sha256=111,5"#,
        "\r\n\r\n",
        r#""pkg/file""with""quotes.txt",sha256=222,6"#,
        "\npkg/single_column_flexible\npkg-1.0.dist-info/RECORD,,\r\n",
    );
    let paths = parse_record(csv_bytes.as_bytes()).unwrap();
    assert_eq!(
        paths,
        vec![
            "pkg/file,with,commas.txt",
            r#"pkg/file"with"quotes.txt"#,
            "pkg/single_column_flexible",
            "pkg-1.0.dist-info/RECORD",
        ]
    );
}

#[test]
fn test_get_wheel_record() {
    let expected = vec![
        "examples/wheel/lib/data,with,commas.txt",
        "examples/wheel/lib/data.txt",
        "examples/wheel/lib/module_with_data.py",
        "examples/wheel/lib/module_with_type_annotations.py",
        "examples/wheel/lib/module_with_type_annotations.pyi",
        "examples/wheel/lib/simple_module.py",
        "examples/wheel/main.py",
        "example_minimal_package-0.0.1.dist-info/WHEEL",
        "example_minimal_package-0.0.1.dist-info/METADATA",
        "example_minimal_package-0.0.1.dist-info/RECORD",
    ];

    let example_wheel = Path::new(EXAMPLE_WHEEL_REL_PATH);
    let record = read_wheel_record(example_wheel).unwrap();
    assert_eq!(record, expected);

    let tmp = TempDir::new("get_record");
    let synth_whl = tmp.path().join("synth.whl");
    create_synthetic_minimal_wheel(&synth_whl, CompressionMethod::Stored, None);
    let record = read_wheel_record(&synth_whl).unwrap();
    assert_eq!(record, expected);
}

#[test]
fn test_get_files_with_pattern_and_empty() {
    let tmp = TempDir::new("get_files");
    let whl_path = tmp.path().join("minimal.whl");
    create_synthetic_minimal_wheel(&whl_path, CompressionMethod::Deflated, None);

    let record = read_wheel_record(&whl_path).unwrap();

    // Pattern from tests/whl_filegroup/extract_wheel_files_test.py
    let regex = compile_pattern(r"(examples/wheel/lib/.*\.txt$|.*main)").unwrap();
    let files = get_files(&record, &regex);
    let expected = vec![
        "examples/wheel/lib/data,with,commas.txt",
        "examples/wheel/lib/data.txt",
        "examples/wheel/main.py",
    ];
    assert_eq!(files, expected);

    // Empty pattern matches all files in RECORD
    let empty_regex = compile_pattern("").unwrap();
    let all_files = get_files(&record, &empty_regex);
    assert_eq!(all_files, record);
}

#[test]
fn test_extract_files() {
    let files = [
        "examples/wheel/lib/data,with,commas.txt",
        "examples/wheel/lib/data.txt",
        "examples/wheel/main.py",
    ];
    let expected_set: HashSet<String> = files.iter().map(|s| (*s).to_string()).collect();

    let example_wheel = Path::new(EXAMPLE_WHEEL_REL_PATH);
    let tmp_real = TempDir::new("extract_real");
    let outdir_real = tmp_real.path().join("out");
    extract_wheel_entries(example_wheel, files, &outdir_real).unwrap();
    let extracted_real = collect_extracted_files(&outdir_real);
    assert_eq!(extracted_real, expected_set);

    let tmp = TempDir::new("extract_synth");
    let synth_whl = tmp.path().join("synth.whl");
    create_synthetic_minimal_wheel(&synth_whl, CompressionMethod::Deflated, None);
    let outdir = tmp.path().join("out");
    extract_wheel_entries(&synth_whl, files, &outdir).unwrap();
    let extracted = collect_extracted_files(&outdir);
    assert_eq!(extracted, expected_set);
    assert_eq!(
        fs::read_to_string(outdir.join("examples/wheel/lib/data,with,commas.txt")).unwrap(),
        "comma,data\n"
    );
}

#[test]
fn test_invalid_zip_error() {
    let tmp = TempDir::new("invalid_zip");
    let bad_zip = tmp.path().join("not_a_zip.whl");
    fs::write(&bad_zip, b"not a zip archive at all").unwrap();

    let err = read_wheel_record(&bad_zip).unwrap_err();
    assert_eq!(
        err.to_string(),
        format!("{} is not a valid zip file", bad_zip.display())
    );

    let short_zip = tmp.path().join("short.whl");
    fs::write(&short_zip, b"short").unwrap();
    let err2 = read_wheel_record(&short_zip).unwrap_err();
    assert_eq!(
        err2.to_string(),
        format!("{} is not a valid zip file", short_zip.display())
    );

    // A missing file is an open error, not a "not a valid zip file" error.
    let missing = tmp.path().join("missing.whl");
    let err3 = read_wheel_record(&missing).unwrap_err();
    assert_eq!(err3.to_string(), format!("opening {}", missing.display()));
}

#[test]
fn test_missing_or_multiple_record_files_error() {
    let tmp = TempDir::new("record_count");

    // 0 .dist-info/RECORD files
    let zero_rec_whl = tmp.path().join("zero_record.whl");
    write_test_zip(
        &zero_rec_whl,
        &[("pkg/mod.py", b"x = 1\n", CompressionMethod::Stored)],
        None,
    );
    let err_zero = read_wheel_record(&zero_rec_whl).unwrap_err();
    assert_eq!(
        err_zero.to_string(),
        format!(
            "{} doesn't contain exactly one .dist-info/RECORD",
            zero_rec_whl.display()
        )
    );

    // 2 .dist-info/RECORD files
    let two_rec_whl = tmp.path().join("two_record.whl");
    write_test_zip(
        &two_rec_whl,
        &[
            (
                "a-1.0.dist-info/RECORD",
                b"a-1.0.dist-info/RECORD,,\n",
                CompressionMethod::Stored,
            ),
            (
                "b-1.0.dist-info/RECORD",
                b"b-1.0.dist-info/RECORD,,\n",
                CompressionMethod::Stored,
            ),
        ],
        None,
    );
    let err_two = read_wheel_record(&two_rec_whl).unwrap_err();
    assert_eq!(
        err_two.to_string(),
        format!(
            "{} doesn't contain exactly one .dist-info/RECORD",
            two_rec_whl.display()
        )
    );
}

#[test]
fn test_csv_quoted_paths_and_deflated_entries() {
    let tmp = TempDir::new("csv_and_deflate");
    let whl_path = tmp.path().join("special.whl");
    let record_csv = concat!(
        r#""pkg/file,with,commas.txt",sha256=111,5"#,
        "\r\n",
        r#""pkg/file""with""quotes.txt",sha256=222,6"#,
        "\r\npkg/deflated.txt,sha256=333,1300\r\nspecial-1.0.dist-info/RECORD,,\r\n",
    );
    let repeated = b"hello wheel! ".repeat(100);
    write_test_zip(
        &whl_path,
        &[
            (
                "pkg/file,with,commas.txt",
                b"hello",
                CompressionMethod::Stored,
            ),
            (
                r#"pkg/file"with"quotes.txt"#,
                b"quotes",
                CompressionMethod::Deflated,
            ),
            ("pkg/deflated.txt", &repeated, CompressionMethod::Deflated),
            (
                "special-1.0.dist-info/RECORD",
                record_csv.as_bytes(),
                CompressionMethod::Deflated,
            ),
        ],
        None,
    );

    let record = read_wheel_record(&whl_path).unwrap();
    assert_eq!(
        record,
        vec![
            "pkg/file,with,commas.txt",
            r#"pkg/file"with"quotes.txt"#,
            "pkg/deflated.txt",
            "special-1.0.dist-info/RECORD",
        ]
    );

    // Extract paths valid on all filesystems (`"` is forbidden in NTFS/Win32 filenames).
    let outdir = tmp.path().join("extracted");
    let opts = Options {
        whl_path: whl_path.clone(),
        outdir: outdir.clone(),
        regex: compile_pattern(r"pkg/(?:file,with|deflated).*").unwrap(),
    };
    run(&opts).unwrap();

    assert_eq!(
        fs::read(outdir.join("pkg/file,with,commas.txt")).unwrap(),
        b"hello"
    );
    assert_eq!(fs::read(outdir.join("pkg/deflated.txt")).unwrap(), repeated);
    assert!(!outdir.join("special-1.0.dist-info/RECORD").exists());

    #[cfg(unix)]
    {
        let unix_outdir = tmp.path().join("extracted_unix");
        let unix_opts = Options {
            whl_path,
            outdir: unix_outdir.clone(),
            regex: compile_pattern(r#"pkg/file"with"quotes\.txt"#).unwrap(),
        };
        run(&unix_opts).unwrap();
        assert_eq!(
            fs::read(unix_outdir.join(r#"pkg/file"with"quotes.txt"#)).unwrap(),
            b"quotes"
        );
    }
}

#[test]
fn test_empty_match_still_creates_outdir() {
    let tmp = TempDir::new("empty_match");
    let whl_path = tmp.path().join("test.whl");
    create_synthetic_minimal_wheel(&whl_path, CompressionMethod::Stored, None);

    let outdir = tmp.path().join("nested/empty_out_dir");
    let opts = Options {
        whl_path,
        outdir: outdir.clone(),
        regex: compile_pattern("nonexistent_prefix/.*").unwrap(),
    };
    run(&opts).unwrap();
    assert!(outdir.is_dir());
    assert!(collect_extracted_files(&outdir).is_empty());
}

#[test]
fn test_parse_args_and_usage() {
    let opts2 = parse_options(["foo.whl", "out_dir"]);
    assert_eq!(opts2.whl_path, PathBuf::from("foo.whl"));
    assert_eq!(opts2.outdir, PathBuf::from("out_dir"));
    assert!(opts2.regex.is_match("anything/at/all.py"));

    let opts3 = parse_options(["foo.whl", "out_dir", r"numpy/.*\.h$"]);
    assert_eq!(opts3.whl_path, PathBuf::from("foo.whl"));
    assert_eq!(opts3.outdir, PathBuf::from("out_dir"));
    assert!(opts3.regex.is_match("numpy/core/api.h"));
    assert!(!opts3.regex.is_match("other/numpy/core/api.h"));

    assert!(matches!(parse_args(["--help"]), Ok(ParsedArgs::Help)));
    assert!(matches!(parse_args(["-h"]), Ok(ParsedArgs::Help)));
    assert!(matches!(
        parse_args(["foo.whl", "--help", "out_dir"]),
        Ok(ParsedArgs::Help)
    ));

    for bad in [vec![], vec!["only_wheel.whl"], vec!["a", "b", "c", "d"]] {
        let err = parse_args(bad.clone()).unwrap_err().to_string();
        assert!(
            err.contains("expected 2 or 3 positional arguments"),
            "unexpected error for {bad:?}: {err}"
        );
    }

    let err_flag = parse_args(["--bogus", "foo.whl", "out_dir"])
        .unwrap_err()
        .to_string();
    assert!(err_flag.contains("--bogus"), "unexpected error: {err_flag}");

    let err_bad_regex = parse_args(["foo.whl", "out_dir", "[unclosed"])
        .unwrap_err()
        .to_string();
    assert!(
        err_bad_regex.contains("invalid regex"),
        "unexpected error: {err_bad_regex}"
    );
}

#[test]
fn test_regex_re_match_semantics_and_complex_patterns() {
    let filter = |entries: &[&str], pat: &str| {
        let re = compile_pattern(pat).unwrap();
        get_files(entries, &re)
    };

    // 1. Start-anchoring without end-anchoring (Python re.match semantics)
    let matched = filter(
        &[
            "numpy/core/include/numpy/arrayobject.h",
            "other/numpy/core/include/numpy/arrayobject.h",
        ],
        "numpy/core/include/numpy",
    );
    assert_eq!(matched, vec!["numpy/core/include/numpy/arrayobject.h"]);

    // 1b. Unanchored alternation must still anchor both branches at start
    let matched_alt = filter(&["foo/a.py", "bar/b.py", "prefix/bar/b.py"], "foo|bar");
    assert_eq!(matched_alt, vec!["foo/a.py", "bar/b.py"]);

    // 2. Header pattern from tests/whl_filegroup/BUILD.bazel
    let matched_hdr = filter(
        &[
            "tests/whl_filegroup/include/whl_headers/header.h",
            "tests/whl_filegroup/lib.py",
        ],
        r"tests/whl_filegroup/include/.*\.h",
    );
    assert_eq!(
        matched_hdr,
        vec!["tests/whl_filegroup/include/whl_headers/header.h"]
    );

    // 3. Character classes, ranges, negation, shorthands, and quantifiers
    let matched_complex = filter(
        &[
            "pkg/mod_1/file_42.h",
            "lib/abcde/file_0.cpp",
            "pkg/a/file_42.h",
            "pkg/abcdefg/file_42.h",
            "pkg/mod_1/file_xx.h",
        ],
        r"^(?:pkg|lib)/[a-z_][a-z0-9_]{2,5}/file_\d+\.[ch](?:pp)?$",
    );
    assert_eq!(
        matched_complex,
        vec!["pkg/mod_1/file_42.h", "lib/abcde/file_0.cpp"]
    );

    // 4. Negated character class and word boundaries
    let matched_neg = filter(
        &["pkg/main.py", "pkg/sub/main.py", "pkg/main2.py"],
        r"[^/]+/\bmain\b\.py$",
    );
    assert_eq!(matched_neg, vec!["pkg/main.py"]);

    // 5. Case-insensitive inline flag (?i) and non-greedy quantifiers
    let matched_ci = filter(&["My_Pkg-1.0.WHL", "My_Pkg-1.0.tar"], r"(?i).*?\.whl$");
    assert_eq!(matched_ci, vec!["My_Pkg-1.0.WHL"]);

    // 6. Character class edge cases: literal ']' first, literal '-' escaped, hex escapes
    let matched_cls = filter(&["]-abc/", "d"], r"^[]\-a-c\x2f]+$");
    assert_eq!(matched_cls, vec!["]-abc/"]);

    // 7. Pathological nested star pattern completes instantaneously without backtracking
    let matched_nfa = filter(&["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaac", "aaaaab"], r"^(a*)*b$");
    assert_eq!(matched_nfa, vec!["aaaaab"]);

    // 8. Invalid regex returns error at compile_pattern / parse_args time
    assert!(compile_pattern("[unclosed").is_err());
    assert!(compile_pattern("(unclosed").is_err());
    assert!(compile_pattern("a{5,2}").is_err());
    assert!(compile_pattern("[z-a]").is_err());
}

#[test]
fn test_zip_with_archive_comment_and_crc_mismatch() {
    let tmp = TempDir::new("comment_and_crc");
    let whl_path = tmp.path().join("with_comment.whl");
    create_synthetic_minimal_wheel(
        &whl_path,
        CompressionMethod::Stored,
        Some("wheel comment!!"),
    );

    let record = read_wheel_record(&whl_path).unwrap();
    assert_eq!(record.len(), 10);

    // Corrupt a byte inside the first stored entry's payload and verify CRC error detection.
    let mut bytes = fs::read(&whl_path).unwrap();
    let needle = b"comma,data\n";
    let pos = bytes
        .windows(needle.len())
        .position(|w| w == needle)
        .unwrap();
    bytes[pos] ^= 0xFF;
    let corrupted_whl = tmp.path().join("corrupted.whl");
    fs::write(&corrupted_whl, &bytes).unwrap();

    let outdir = tmp.path().join("out_corrupt");
    let err = extract_wheel_entries(
        &corrupted_whl,
        ["examples/wheel/lib/data,with,commas.txt"],
        &outdir,
    )
    .unwrap_err();
    let err = format!("{err:#}").to_lowercase();
    assert!(
        err.contains("checksum") || err.contains("crc"),
        "unexpected error: {err}"
    );
}

#[test]
fn test_run_cli_and_subprocess() {
    let tmp = TempDir::new("cli_direct");
    let whl_path = tmp.path().join("cli.whl");
    create_synthetic_minimal_wheel(&whl_path, CompressionMethod::Deflated, None);
    let outdir = tmp.path().join("extracted_direct");

    assert_eq!(run_cli(["only_one_arg"]), ExitCode::FAILURE);
    assert_eq!(
        run_cli([
            whl_path.as_os_str(),
            outdir.as_os_str(),
            std::ffi::OsStr::new(r"(examples/wheel/lib/.*\.txt$|.*main)"),
        ]),
        ExitCode::SUCCESS
    );
    let expected: HashSet<String> = [
        "examples/wheel/lib/data,with,commas.txt",
        "examples/wheel/lib/data.txt",
        "examples/wheel/main.py",
    ]
    .into_iter()
    .map(String::from)
    .collect();
    assert_eq!(collect_extracted_files(&outdir), expected);

    let bin_candidates = [
        "crates/shrubbery/shrubbery",
        "crates/shrubbery/shrubbery.exe",
    ];
    let bin_path = bin_candidates
        .iter()
        .map(Path::new)
        .find(|p| p.exists())
        .expect("shrubbery binary should exist in runfiles");

    let bad_out = std::process::Command::new(bin_path)
        .arg("extract_wheel_files")
        .arg("only_one_arg")
        .output()
        .unwrap();
    assert_eq!(bad_out.status.code(), Some(1));
    let stderr_str = String::from_utf8_lossy(&bad_out.stderr);
    assert!(
        stderr_str.contains("extract_wheel_files: error:")
            && stderr_str.contains("expected 2 or 3 positional arguments"),
        "unexpected stderr: {stderr_str}"
    );

    let help_out = std::process::Command::new(bin_path)
        .arg("extract_wheel_files")
        .arg("--help")
        .output()
        .unwrap();
    assert_eq!(help_out.status.code(), Some(0));
    let stdout_str = String::from_utf8_lossy(&help_out.stdout);
    assert!(
        stdout_str.contains("Usage: extract_wheel_files <wheel> <out_dir> [regex_pattern]"),
        "unexpected stdout: {stdout_str}"
    );
}

struct TempDir {
    path: PathBuf,
}

impl TempDir {
    fn new(prefix: &str) -> Self {
        let id = TEST_COUNTER.fetch_add(1, Ordering::SeqCst);
        let base = env::var_os("TEST_TMPDIR")
            .map(PathBuf::from)
            .unwrap_or_else(env::temp_dir);
        let path = base.join(format!(
            "extract_wheel_files_test_{}_{}_{}",
            prefix,
            std::process::id(),
            id
        ));
        let _ = fs::remove_dir_all(&path);
        fs::create_dir_all(&path).unwrap();
        Self { path }
    }

    fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

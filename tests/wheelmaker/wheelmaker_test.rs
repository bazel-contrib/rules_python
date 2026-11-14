use std::collections::HashMap;
use std::env;
use std::fs::{self, File};
use std::io::{Cursor, Read, Seek};
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::atomic::{AtomicUsize, Ordering};

use sha2::{Digest, Sha256};
use wheelmaker_lib::{
    Cli, Options, REGULAR_FILE_UNIX_MODE, WhlFile, arcname_from, build_wheel,
    escape_filename_distribution_name, expand_metadata_requires, get_new_requirement_line,
    normalize_package_name, normalize_pep440, parse_args, resolve_stamp_with_lines, run_cli,
    serialize_digest,
};
use zip::{CompressionMethod, DateTime, System, ZipArchive};

static TEST_COUNTER: AtomicUsize = AtomicUsize::new(0);

fn unwrap_run_options(cli: Cli) -> Options {
    match cli {
        Cli::Run(opts) => *opts,
        Cli::Help => panic!("expected Cli::Run, got Cli::Help"),
    }
}

fn read_zip_entries_from_reader<R: Read + Seek>(reader: R) -> Vec<ParsedZipEntry> {
    let mut archive = ZipArchive::new(reader).expect("output zip should be a valid archive");
    let mut entries = Vec::with_capacity(archive.len());
    for idx in 0..archive.len() {
        let mut entry = archive.by_index(idx).expect("zip entry should be readable");
        let name = entry
            .name()
            .expect("zip entry name should be valid UTF-8")
            .into_owned();
        let system = entry.system();
        let compression = entry.compression();
        let last_modified = entry.last_modified();
        let unix_mode = entry.unix_mode();
        let file_size = entry.size();
        let mut data = Vec::with_capacity(file_size as usize);
        entry
            .read_to_end(&mut data)
            .expect("zip entry payload should decompress cleanly");
        assert_eq!(
            data.len() as u64,
            file_size,
            "uncompressed size mismatch for {name}"
        );

        entries.push(ParsedZipEntry {
            name,
            system,
            compression,
            last_modified,
            unix_mode,
            file_size,
            data,
        });
    }

    entries
}

fn read_zip_entries(zip_path: &Path) -> Vec<ParsedZipEntry> {
    let file = File::open(zip_path).expect("zip file should be readable");
    read_zip_entries_from_reader(file)
}

fn assert_reproducible_metadata(entries: &[ParsedZipEntry], expected_method: CompressionMethod) {
    for entry in entries {
        assert_eq!(entry.system, System::Unix, "{}", entry.name);
        assert_eq!(
            entry.last_modified,
            Some(DateTime::DEFAULT),
            "{}",
            entry.name
        );
        assert_eq!(
            entry.unix_mode,
            Some(REGULAR_FILE_UNIX_MODE),
            "{}",
            entry.name
        );
        assert_eq!(entry.compression, expected_method, "{}", entry.name);
        assert_eq!(entry.file_size, entry.data.len() as u64, "{}", entry.name);
    }
}

#[test]
fn test_record_csv_quoting() {
    let mut sha_a = Sha256::new();
    sha_a.update(b"a");
    let digest_a = serialize_digest(&sha_a.finalize());

    let mut whl = WhlFile::new(Cursor::new(Vec::new()), "test-1.0.0", Vec::new(), "", true);
    whl.add_string("foo/bar.py", b"a")
        .expect("simple path should be writable");
    whl.add_string("foo,bar/baz.py", b"a")
        .expect("comma path should be writable");
    whl.add_string("/leading/slash.py", b"a")
        .expect("leading-slash path should be writable");
    whl.add_string(r"\leading\backslash.py", b"a")
        .expect("leading-backslash path should be writable");
    whl.add_string("has\"quote.py", b"a")
        .expect("quote path should be writable");
    let record = whl
        .add_recordfile()
        .expect("RECORD entry should be writable");
    let cursor = whl.finish().expect("in-memory wheel should finalize");
    let entries = read_zip_entries_from_reader(Cursor::new(cursor.into_inner()));
    assert_reproducible_metadata(&entries, CompressionMethod::Deflated);
    let names: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
    assert_eq!(
        names,
        vec![
            "foo/bar.py",
            "foo,bar/baz.py",
            "leading/slash.py",
            r"leading\backslash.py",
            "has\"quote.py",
            "test-1.0.0.dist-info/RECORD",
        ]
    );

    assert_eq!(
        record,
        format!(
            concat!(
                "foo/bar.py,{digest_a},1\n",
                "\"foo,bar/baz.py\",{digest_a},1\n",
                "leading/slash.py,{digest_a},1\n",
                "leading\\backslash.py,{digest_a},1\n",
                "\"has\"\"quote.py\",{digest_a},1\n",
                "test-1.0.0.dist-info/RECORD,,\n",
            ),
            digest_a = digest_a,
        )
    );
}

#[test]
fn test_arcname_from() {
    struct Case<'a> {
        name: &'a str,
        distribution_prefix: &'a str,
        strip_path_prefixes: &'a [&'a str],
        add_path_prefix: &'a str,
        expected: &'a str,
    }

    let cases = [
        Case {
            name: "a/b/c/file.py",
            distribution_prefix: "",
            strip_path_prefixes: &[],
            add_path_prefix: "",
            expected: "a/b/c/file.py",
        },
        Case {
            name: "a/b/c/file.py",
            distribution_prefix: "",
            strip_path_prefixes: &["a"],
            add_path_prefix: "",
            expected: "/b/c/file.py",
        },
        Case {
            name: "a/b/c/file.py",
            distribution_prefix: "",
            strip_path_prefixes: &["a/b/"],
            add_path_prefix: "",
            expected: "c/file.py",
        },
        Case {
            name: r"a\b\c\file.py",
            distribution_prefix: "",
            strip_path_prefixes: &["a/b/"],
            add_path_prefix: "",
            expected: "c/file.py",
        },
        Case {
            name: "a/b/c/file.py",
            distribution_prefix: "",
            strip_path_prefixes: &["a/", "b/"],
            add_path_prefix: "",
            expected: "b/c/file.py",
        },
        Case {
            name: "foo/bar/baz/file.py",
            distribution_prefix: "",
            strip_path_prefixes: &["foo", "foo/bar/baz"],
            add_path_prefix: "",
            expected: "/bar/baz/file.py",
        },
        Case {
            name: "foo/bar/baz/file.py",
            distribution_prefix: "",
            strip_path_prefixes: &["foo/bar/baz", "foo"],
            add_path_prefix: "",
            expected: "/file.py",
        },
        Case {
            name: "foo/file2.py",
            distribution_prefix: "",
            strip_path_prefixes: &["foo/bar/baz", "foo"],
            add_path_prefix: "",
            expected: "/file2.py",
        },
        Case {
            name: "mylib-0.0.1-dist-info/WHEEL",
            distribution_prefix: "mylib",
            strip_path_prefixes: &[],
            add_path_prefix: "",
            expected: "mylib-0.0.1-dist-info/WHEEL",
        },
        Case {
            name: "mylib/a/b/c/WHEEL",
            distribution_prefix: "mylib",
            strip_path_prefixes: &["mylib"],
            add_path_prefix: "",
            expected: "mylib/a/b/c/WHEEL",
        },
        Case {
            name: "a/b/c/file.py",
            distribution_prefix: "",
            strip_path_prefixes: &[],
            add_path_prefix: "namespace/",
            expected: "namespace/a/b/c/file.py",
        },
        Case {
            name: "a/b/c/file.py",
            distribution_prefix: "",
            strip_path_prefixes: &["a"],
            add_path_prefix: "namespace",
            expected: "namespace/b/c/file.py",
        },
        Case {
            name: "a/b/c/file.py",
            distribution_prefix: "",
            strip_path_prefixes: &["a/b/"],
            add_path_prefix: "namespace_",
            expected: "namespace_c/file.py",
        },
        Case {
            name: "a/b/c/file.py",
            distribution_prefix: "",
            strip_path_prefixes: &["a/b/"],
            add_path_prefix: r"namespace\sub\",
            expected: "namespace/sub/c/file.py",
        },
    ];

    for c in cases {
        let prefixes: Vec<String> = c
            .strip_path_prefixes
            .iter()
            .map(|s| (*s).to_string())
            .collect();
        let got = arcname_from(c.name, c.distribution_prefix, &prefixes, c.add_path_prefix);
        assert_eq!(got, c.expected, "case: {}", c.name);
    }
}

#[test]
fn test_get_new_requirement_line() {
    assert_eq!(
        get_new_requirement_line("requests>=2.0", "").expect("requirement should parse"),
        "Requires-Dist: requests>=2.0"
    );
    assert_eq!(
        get_new_requirement_line("requests>=2.0", "extra=='dev'")
            .expect("requirement with extra should parse"),
        "Requires-Dist: requests>=2.0; extra == 'dev'"
    );
    assert_eq!(
        get_new_requirement_line(
            "requests @ git+https://github.com/psf/requests.git@3aa6386c3",
            ""
        )
        .expect("URL requirement should parse"),
        "Requires-Dist: requests @ git+https://github.com/psf/requests.git@3aa6386c3"
    );
    assert_eq!(
        get_new_requirement_line(
            "requests @ https://example.com/requests-2.0.whl",
            "extra == 'dev'"
        )
        .expect("URL requirement with extra should parse"),
        "Requires-Dist: requests @ https://example.com/requests-2.0.whl ; extra == 'dev'"
    );
    assert_eq!(
        get_new_requirement_line("requests>=2.0; python_version>='3.6'", "")
            .expect("marker requirement should parse"),
        "Requires-Dist: requests>=2.0; python_full_version >= '3.6'"
    );
    assert_eq!(
        get_new_requirement_line("requests>=2.0; python_version>='3.6'", "extra=='dev'")
            .expect("marker + extra requirement should parse"),
        "Requires-Dist: requests>=2.0; python_full_version >= '3.6' and extra == 'dev'"
    );
    assert_eq!(
        get_new_requirement_line("pyyaml>=6.0.0,!=6.0.1", "extra == 'example'")
            .expect("multi-specifier requirement should parse"),
        "Requires-Dist: pyyaml!=6.0.1,>=6.0.0; extra == 'example'"
    );
    assert_eq!(
        get_new_requirement_line(
            concat!(
                "toml; (python_version == \"3.11\" or python_version == \"3.12\") ",
                "and python_version != \"3.8\"",
            ),
            "extra == 'example'"
        )
        .expect("compound marker requirement should parse"),
        concat!(
            "Requires-Dist: toml; python_full_version >= '3.11' and ",
            "python_full_version < '3.13' and extra == 'example'",
        )
    );
    assert_eq!(
        get_new_requirement_line(
            "wheel; python_version == \"3.11\" or python_version == \"3.12\" ",
            "extra == 'example'"
        )
        .expect("trailing-space marker requirement should parse"),
        concat!(
            "Requires-Dist: wheel; python_full_version >= '3.11' and ",
            "python_full_version < '3.13' and extra == 'example'",
        )
    );
    assert_eq!(
        get_new_requirement_line("extra_requires[example]==0.0.1", "")
            .expect("extra dependency requirement should parse"),
        "Requires-Dist: extra-requires[example]==0.0.1"
    );
    assert_eq!(
        get_new_requirement_line(
            "baz~=1.2.3; extra == 'test_extra' or 'dev.extra' == extra",
            ""
        )
        .expect("extra marker normalization should succeed"),
        "Requires-Dist: baz~=1.2.3; extra == 'dev-extra' or extra == 'test-extra'"
    );
    assert_eq!(
        get_new_requirement_line(
            "baz~=1.2.3; extra == 'test_extra' or 'dev.extra' == extra",
            "extra == 'dev.extra'"
        )
        .expect("extra marker conjunction should simplify"),
        "Requires-Dist: baz~=1.2.3; extra == 'dev-extra'"
    );

    let bad_req = format!(
        "{:#}",
        get_new_requirement_line("not a valid === req ???", "").unwrap_err()
    );
    assert!(
        bad_req.contains("parsing requirement"),
        "unexpected error: {bad_req}"
    );
    let bad_marker = format!(
        "{:#}",
        get_new_requirement_line("requests>=2.0", "not_a_marker == 'x'").unwrap_err()
    );
    assert!(
        bad_marker.contains("parsing extra marker"),
        "unexpected error: {bad_marker}"
    );
}

#[test]
fn test_escaping_and_pep440_normalization() {
    assert_eq!(
        normalize_package_name("File--Name_Escaping.Pkg")
            .expect("package name normalization should succeed"),
        "file-name-escaping-pkg"
    );
    assert_eq!(
        escape_filename_distribution_name("File--Name-Escaping")
            .expect("distribution escaping should succeed"),
        "file_name_escaping"
    );

    assert_eq!(
        normalize_pep440("v0.0.1.RC1+ubuntu-r7").expect("PEP 440 version should normalize"),
        "0.0.1rc1+ubuntu.r7"
    );
    assert_eq!(
        normalize_pep440("01.02.003").expect("zero-padded PEP 440 version should normalize"),
        "1.2.3"
    );
    assert_eq!(
        normalize_pep440("1.2.3.dev0").expect("dev version should normalize"),
        "1.2.3.dev0"
    );
    assert_eq!(
        normalize_pep440("1.0-2").expect("implicit post version should normalize"),
        "1.0.post2"
    );
    assert_eq!(
        normalize_pep440("1!2.0.rev3").expect("epoch + rev version should normalize"),
        "1!2.0.post3"
    );
    assert_eq!(
        normalize_pep440("0.1.{BUILD_TIMESTAMP}")
            .expect("unstamped placeholder version should normalize"),
        "0.1.0+0.1.build.timestamp"
    );
    assert_eq!(
        normalize_pep440("{BUILD_EMBED_LABEL}").expect("bare placeholder version should normalize"),
        "0+build.embed.label"
    );
    assert_eq!(
        normalize_pep440("1.0+local.{STAMP}")
            .expect("local + placeholder version should normalize"),
        "1.0+local.0.1.0.local.stamp"
    );
    assert_eq!(
        normalize_pep440("invalid_ver").expect("fallback local version should normalize"),
        "0+invalid.ver"
    );

    assert!(normalize_pep440("").is_err());
    assert!(normalize_pep440("---").is_err());
}

#[test]
fn test_expand_metadata_requires_shared_file_with_and_without_extra() {
    let tmp = TempDir::new("shared_reqs");
    let reqs_file = tmp.path().join("shared.txt");
    fs::write(&reqs_file, "tomli>=2.0.0\r\nstarlark # inline comment\r\n")
        .expect("shared.txt should be writable");

    // Regression check: when the same @file path appears both bare and with `; extra == '...'`,
    // expanding the bare directive must not corrupt the extra directive's line; `\r\n` inputs are
    // handled directly via `str::lines` and emitted with `\n`.
    let raw = format!(
        concat!(
            "Metadata-Version: 2.1\r\n",
            "Name: shared\r\n",
            "Requires-Dist: @{reqs}\r\n",
            "Provides-Extra: dev\r\n",
            "Requires-Dist: @{reqs}; extra == 'dev'\r\n",
        ),
        reqs = reqs_file.display(),
    );
    let expanded = expand_metadata_requires(&raw).expect("metadata expansion should succeed");
    assert_eq!(
        expanded,
        concat!(
            "Metadata-Version: 2.1\n",
            "Name: shared\n",
            "Requires-Dist: tomli>=2.0.0\n",
            "Requires-Dist: starlark\n",
            "Provides-Extra: dev\n",
            "Requires-Dist: tomli>=2.0.0; extra == 'dev'\n",
            "Requires-Dist: starlark; extra == 'dev'\n",
        )
    );
}

#[test]
fn test_end_to_end_customized_wheel_and_record() {
    let tmp = TempDir::new("customized");
    let data_commas = tmp.path().join("data,with,commas.txt");
    fs::write(&data_commas, b"hello world\n").expect("comma data file should be writable");

    let empty_pyi = tmp.path().join("mod.pyi");
    fs::write(&empty_pyi, b"").expect("empty pyi file should be writable");

    let sub_dir = tmp.path().join("someDir");
    fs::create_dir_all(&sub_dir).expect("sub_dir should be creatable");
    fs::write(sub_dir.join("zed.py"), b"y = 2\n").expect("zed.py should be writable");
    fs::write(sub_dir.join("foo.py"), b"x = 1\n").expect("foo.py should be writable");

    let input_list_path = tmp.path().join("inputs.txt");
    fs::write(
        &input_list_path,
        format!(
            concat!(
                "examples/wheel/lib/data,with,commas.txt;{}\n",
                "examples/wheel/lib/mod.pyi;{}\n",
                "examples/wheel/someDir;{}\n",
            ),
            data_commas.display(),
            empty_pyi.display(),
            sub_dir.display(),
        ),
    )
    .expect("input_file_list should be writable");

    let reqs_file = tmp.path().join("requires.txt");
    fs::write(
        &reqs_file,
        "# comment\n--index-url https://pypi.org\n\ntomli>=2.0.0\nstarlark  # inline comment\n",
    )
    .expect("requires.txt should be writable");

    let extra_reqs_file = tmp.path().join("extra_requires.txt");
    fs::write(
        &extra_reqs_file,
        concat!(
            "pyyaml>=6.0.0,!=6.0.1\n",
            "toml; (python_version == \"3.11\" or python_version == \"3.12\") ",
            "and python_version != \"3.8\"\n",
        ),
    )
    .expect("extra_requires.txt should be writable");

    let metadata_file = tmp.path().join("metadata.txt");
    fs::write(
        &metadata_file,
        format!(
            concat!(
                "Metadata-Version: 2.1\n",
                "Name: File--Name-Escaping\n",
                "Author: Example Author: żółw\n",
                "Requires-Dist: @{}\n",
                "Provides-Extra: example\n",
                "Requires-Dist: @{}; extra == 'example'\n",
            ),
            reqs_file.display(),
            extra_reqs_file.display(),
        ),
    )
    .expect("metadata.txt should be writable");

    let desc_file = tmp.path().join("README.md");
    fs::write(&desc_file, b"This is a sample description of a wheel.")
        .expect("README.md should be writable");

    let ep_file = tmp.path().join("entry_points.txt");
    fs::write(&ep_file, b"[console_scripts]\nmain = foo.bar:baz")
        .expect("entry_points.txt should be writable");

    let notice_file = tmp.path().join("NOTICE");
    fs::write(&notice_file, b"Notice text\n").expect("NOTICE should be writable");

    let out_whl = tmp.path().join("nested").join("out.whl");
    let name_file = tmp.path().join("nested_name").join("out.name");

    let opts = unwrap_run_options(
        parse_args([
            "--name",
            "File--Name-Escaping",
            "--version",
            "v0.0.1.RC1+ubuntu-r7",
            "--python_tag",
            "py3",
            "--abi",
            "none",
            "--platform",
            "any",
            "--out",
            out_whl.to_str().expect("out_whl path should be UTF-8"),
            "--name_file",
            name_file.to_str().expect("name_file path should be UTF-8"),
            "--strip_path_prefix=examples/wheel/",
            "--path_prefix=pkg/",
            "--input_file_list",
            input_list_path
                .to_str()
                .expect("input_list_path should be UTF-8"),
            "--metadata_file",
            metadata_file
                .to_str()
                .expect("metadata_file path should be UTF-8"),
            "--description_file",
            desc_file.to_str().expect("desc_file path should be UTF-8"),
            "--entry_points_file",
            ep_file.to_str().expect("ep_file path should be UTF-8"),
            "--extra_distinfo_file",
            &format!("README;{}", desc_file.display()),
            "--extra_distinfo_file",
            &format!("NOTICE;{}", notice_file.display()),
            "--data_files",
            &format!("scripts/NOTICE;{}", notice_file.display()),
            "--data_files",
            &format!("data/README.md;{}", desc_file.display()),
        ])
        .expect("customized wheel args should parse"),
    );

    build_wheel(&opts).expect("build_wheel should succeed");

    assert_eq!(
        fs::read_to_string(&name_file).expect("name_file should be readable"),
        "file_name_escaping-0.0.1rc1+ubuntu.r7-py3-none-any.whl"
    );

    let entries = read_zip_entries(&out_whl);
    assert_reproducible_metadata(&entries, CompressionMethod::Deflated);

    let names: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
    assert_eq!(
        names,
        vec![
            "pkg/lib/data,with,commas.txt",
            "pkg/lib/mod.pyi",
            "pkg/someDir/foo.py",
            "pkg/someDir/zed.py",
            "file_name_escaping-0.0.1rc1+ubuntu.r7.dist-info/WHEEL",
            "file_name_escaping-0.0.1rc1+ubuntu.r7.dist-info/METADATA",
            "file_name_escaping-0.0.1rc1+ubuntu.r7.dist-info/entry_points.txt",
            "file_name_escaping-0.0.1rc1+ubuntu.r7.data/data/README.md",
            "file_name_escaping-0.0.1rc1+ubuntu.r7.data/scripts/NOTICE",
            "file_name_escaping-0.0.1rc1+ubuntu.r7.dist-info/NOTICE",
            "file_name_escaping-0.0.1rc1+ubuntu.r7.dist-info/README",
            "file_name_escaping-0.0.1rc1+ubuntu.r7.dist-info/RECORD",
        ]
    );

    let by_name: HashMap<String, ParsedZipEntry> =
        entries.into_iter().map(|e| (e.name.clone(), e)).collect();

    assert_eq!(
        by_name["file_name_escaping-0.0.1rc1+ubuntu.r7.dist-info/WHEEL"].text(),
        concat!(
            "Wheel-Version: 1.0\n",
            "Generator: bazel-wheelmaker 1.0\n",
            "Root-Is-Purelib: true\n",
            "Tag: py3-none-any\n",
        )
    );

    assert_eq!(
        by_name["file_name_escaping-0.0.1rc1+ubuntu.r7.dist-info/METADATA"].text(),
        concat!(
            "Metadata-Version: 2.1\n",
            "Name: File--Name-Escaping\n",
            "Author: Example Author: żółw\n",
            "Requires-Dist: tomli>=2.0.0\n",
            "Requires-Dist: starlark\n",
            "Provides-Extra: example\n",
            "Requires-Dist: pyyaml!=6.0.1,>=6.0.0; extra == 'example'\n",
            "Requires-Dist: toml; python_full_version >= '3.11' and ",
            "python_full_version < '3.13' and extra == 'example'\n",
            "Version: 0.0.1rc1+ubuntu.r7\n\n",
            "This is a sample description of a wheel.\n",
        )
    );

    let record_text = by_name["file_name_escaping-0.0.1rc1+ubuntu.r7.dist-info/RECORD"].text();
    let record_lines: Vec<&str> = record_text.lines().collect();
    assert_eq!(record_lines.len(), 12);
    let mut sha = Sha256::new();
    sha.update(b"hello world\n");
    let expected_first = format!(
        "\"pkg/lib/data,with,commas.txt\",{},12",
        serialize_digest(&sha.finalize())
    );
    assert_eq!(record_lines[0], expected_first);
    assert_eq!(
        record_lines[11],
        "file_name_escaping-0.0.1rc1+ubuntu.r7.dist-info/RECORD,,"
    );
}

#[test]
fn test_stamping_semantics_and_empty_requires_and_no_compress() {
    let tmp = TempDir::new("stamping");
    let volatile_file = tmp.path().join("volatile-status.txt");
    fs::write(
        &volatile_file,
        "BUILD_TIMESTAMP 123456\nKEY_WITHOUT_SPACE\n",
    )
    .expect("volatile status file should be writable");

    let stable_file = tmp.path().join("stable-status.txt");
    fs::write(&stable_file, "BUILD_USER alice\n").expect("stable status file should be writable");

    assert_eq!(
        resolve_stamp_with_lines(
            "pkg_{BUILD_USER}_{BUILD_TIMESTAMP}_{KEY_WITHOUT_SPACE}",
            &[
                "BUILD_TIMESTAMP 123456".to_string(),
                "KEY_WITHOUT_SPACE".to_string(),
                "BUILD_USER alice".to_string(),
            ]
        ),
        "pkg_alice_123456_"
    );

    let empty_reqs = tmp.path().join("empty_requires.txt");
    fs::write(&empty_reqs, "\n# only comments\n").expect("empty_requires.txt should be writable");

    // Summary and description intentionally contain `{BUILD_USER}` to verify stamping only
    // resolves `name` and `version` (matching `tools/wheelmaker.py`) and never mutates metadata
    // headers or description prose.
    let metadata_file = tmp.path().join("metadata.txt");
    fs::write(
        &metadata_file,
        format!(
            concat!(
                "Metadata-Version: 2.1\n",
                "Name: my_pkg{{BUILD_USER}}\n",
                "Summary: Literal {{BUILD_USER}} placeholder\n",
                "Requires-Dist: @{}\n",
            ),
            empty_reqs.display()
        ),
    )
    .expect("metadata.txt should be writable");

    let desc_file = tmp.path().join("desc.txt");
    fs::write(
        &desc_file,
        "Line one.\r\nBody mentions {BUILD_TIMESTAMP} literally.",
    )
    .expect("desc.txt should be writable");

    let out_whl = tmp.path().join("stamped.whl");
    let name_file = tmp.path().join("stamped.name");
    let flagfile = tmp.path().join("flags.params");
    fs::write(
        &flagfile,
        format!(
            concat!(
                "--name\nmy_pkg{{BUILD_USER}}\n",
                "--version\n0.1.{{BUILD_TIMESTAMP}}\n",
                "--platform\nmanylinux2014_x86_64\n",
                "--abi\nabi3\n",
                "--python_tag\ncp38\n",
                "--no_compress\n",
                "--out\n{}\n",
                "--name_file\n{}\n",
                "--metadata_file\n{}\n",
                "--description_file\n{}\n",
                "--volatile_status_file\n{}\n",
                "--stable_status_file\n{}\n",
            ),
            out_whl.display(),
            name_file.display(),
            metadata_file.display(),
            desc_file.display(),
            volatile_file.display(),
            stable_file.display(),
        ),
    )
    .expect("flagfile should be writable");

    assert_eq!(
        run_cli([format!("@{}", flagfile.display())]),
        ExitCode::SUCCESS
    );

    assert_eq!(
        fs::read_to_string(&name_file).expect("stamped.name should be readable"),
        "my_pkgalice-0.1.123456-cp38-abi3-manylinux2014_x86_64.whl"
    );

    let entries = read_zip_entries(&out_whl);
    assert_reproducible_metadata(&entries, CompressionMethod::Stored);

    let by_name: HashMap<String, ParsedZipEntry> =
        entries.into_iter().map(|e| (e.name.clone(), e)).collect();

    assert_eq!(
        by_name["my_pkgalice-0.1.123456.dist-info/WHEEL"].text(),
        concat!(
            "Wheel-Version: 1.0\n",
            "Generator: bazel-wheelmaker 1.0\n",
            "Root-Is-Purelib: false\n",
            "Tag: cp38-abi3-manylinux2014_x86_64\n",
        )
    );

    assert_eq!(
        by_name["my_pkgalice-0.1.123456.dist-info/METADATA"].text(),
        concat!(
            "Metadata-Version: 2.1\n",
            "Name: my_pkgalice\n",
            "Summary: Literal {BUILD_USER} placeholder\n",
            "Version: 0.1.123456\n\n",
            "Line one.\n",
            "Body mentions {BUILD_TIMESTAMP} literally.\n",
        )
    );

    // Passing only one status file must leave placeholders unresolved, matching Python
    // `if arguments.volatile_status_file and arguments.stable_status_file:`.
    let half_whl = tmp.path().join("half_stamped.whl");
    let half_name = tmp.path().join("half_stamped.name");
    assert_eq!(
        run_cli([
            "--name",
            "my_pkg{BUILD_USER}",
            "--version",
            "0.1.{BUILD_TIMESTAMP}",
            "--out",
            half_whl.to_str().expect("half_whl path should be UTF-8"),
            "--name_file",
            half_name.to_str().expect("half_name path should be UTF-8"),
            "--metadata_file",
            metadata_file
                .to_str()
                .expect("metadata_file path should be UTF-8"),
            "--volatile_status_file",
            volatile_file
                .to_str()
                .expect("volatile_file path should be UTF-8"),
        ]),
        ExitCode::SUCCESS
    );
    assert_eq!(
        fs::read_to_string(&half_name).expect("half_stamped.name should be readable"),
        "my_pkg{build_user}-0.1.0+0.1.build.timestamp-py3-none-any.whl"
    );
    let half_entries: HashMap<String, ParsedZipEntry> = read_zip_entries(&half_whl)
        .into_iter()
        .map(|e| (e.name.clone(), e))
        .collect();
    assert!(
        half_entries["my_pkg{build_user}-0.1.0+0.1.build.timestamp.dist-info/METADATA"]
            .text()
            .ends_with("\n\nUNKNOWN\n")
    );
}

#[test]
fn test_build_tag_inline_requires_and_duplicate_inputs() {
    let tmp = TempDir::new("build_tag");
    let extra_reqs = tmp.path().join("extra_reqs.txt");
    fs::write(&extra_reqs, "pytest>=7.0\n").expect("extra_reqs.txt should be writable");

    let f_first = tmp.path().join("first.py");
    let f_second = tmp.path().join("second.py");
    fs::write(&f_first, b"v = 1\n").expect("first.py should be writable");
    fs::write(&f_second, b"v = 2\n").expect("second.py should be writable");

    let empty_desc = tmp.path().join("empty_desc.md");
    fs::write(&empty_desc, b"").expect("empty_desc.md should be writable");

    let metadata_file = tmp.path().join("metadata.txt");
    fs::write(
        &metadata_file,
        format!(
            concat!(
                "Metadata-Version: 2.1\n",
                "Name: Demo-Pkg\n",
                "Requires-Dist: extra_requires[example]==0.0.1\n",
                "Requires-Dist: pytest; python_version != \"3.8\"\n",
                "Requires-Dist: six>=1.16.0,!=1.16.1; python_version>='3.8'; extra == 'dev'\n",
                "Provides-Extra: dev\n",
                "Requires-Dist: @{}; extra == 'dev'\n",
            ),
            extra_reqs.display()
        ),
    )
    .expect("metadata.txt should be writable");

    let out_whl = tmp.path().join("demo.whl");
    let name_file = tmp.path().join("demo.name");

    let opts = unwrap_run_options(
        parse_args([
            "--name",
            "Demo-Pkg",
            "--version",
            "1.0.0",
            "--build_tag",
            "1build",
            "--python_tag",
            "py2.py3",
            "--abi",
            "none",
            "--platform",
            "any",
            "--out",
            out_whl.to_str().expect("out_whl path should be UTF-8"),
            "--name_file",
            name_file.to_str().expect("name_file path should be UTF-8"),
            "--metadata_file",
            metadata_file
                .to_str()
                .expect("metadata_file path should be UTF-8"),
            "--description_file",
            empty_desc
                .to_str()
                .expect("empty_desc path should be UTF-8"),
            "--input_file",
            &format!("demo/mod.py;{}", f_first.display()),
            "--input_file",
            &format!("demo/mod.py;{}", f_second.display()),
        ])
        .expect("build_tag wheel args should parse"),
    );

    build_wheel(&opts).expect("build_wheel should succeed");

    assert_eq!(
        fs::read_to_string(&name_file).expect("demo.name should be readable"),
        "demo_pkg-1.0.0-1build-py2.py3-none-any.whl"
    );

    let entries = read_zip_entries(&out_whl);
    assert_reproducible_metadata(&entries, CompressionMethod::Deflated);
    let by_name: HashMap<String, ParsedZipEntry> =
        entries.into_iter().map(|e| (e.name.clone(), e)).collect();

    assert_eq!(by_name["demo/mod.py"].text(), "v = 2\n");
    assert_eq!(
        by_name["demo_pkg-1.0.0.dist-info/WHEEL"].text(),
        concat!(
            "Wheel-Version: 1.0\n",
            "Generator: bazel-wheelmaker 1.0\n",
            "Root-Is-Purelib: true\n",
            "Tag: py2.py3-none-any\n",
        )
    );

    assert_eq!(
        by_name["demo_pkg-1.0.0.dist-info/METADATA"].text(),
        concat!(
            "Metadata-Version: 2.1\n",
            "Name: Demo-Pkg\n",
            "Requires-Dist: extra_requires[example]==0.0.1\n",
            "Requires-Dist: pytest; python_full_version != '3.8.*'\n",
            "Requires-Dist: six!=1.16.1,>=1.16.0; ",
            "python_full_version >= '3.8' and extra == 'dev'\n",
            "Provides-Extra: dev\n",
            "Requires-Dist: pytest>=7.0; extra == 'dev'\n",
            "Version: 1.0.0\n\n",
            "UNKNOWN\n",
        )
    );
}

#[test]
fn test_multi_strip_path_prefix_order_and_no_leading_slash_in_record() {
    let tmp = TempDir::new("multi_prefix");
    let mod_file = tmp.path().join("mod.py");
    let main_file = tmp.path().join("main.py");
    fs::write(&mod_file, b"x = 1\n").expect("mod.py should be writable");
    fs::write(&main_file, b"y = 2\n").expect("main.py should be writable");

    let metadata_file = tmp.path().join("metadata.txt");
    fs::write(&metadata_file, "Metadata-Version: 2.1\nName: roots\n")
        .expect("metadata.txt should be writable");

    let build_with_prefixes = |tag: &str, prefixes: &[&str]| -> Vec<ParsedZipEntry> {
        let out_whl = tmp.path().join(format!("{tag}.whl"));
        let mut args = vec![
            "--name".to_string(),
            "roots".to_string(),
            "--version".to_string(),
            "0.0.1".to_string(),
            "--out".to_string(),
            out_whl
                .to_str()
                .expect("out_whl should be UTF-8")
                .to_string(),
            "--metadata_file".to_string(),
            metadata_file
                .to_str()
                .expect("metadata_file should be UTF-8")
                .to_string(),
            "--input_file".to_string(),
            format!("examples/wheel/lib/mod.py;{}", mod_file.display()),
            "--input_file".to_string(),
            format!("examples/wheel/main.py;{}", main_file.display()),
        ];
        for prefix in prefixes {
            args.push(format!("--strip_path_prefix={prefix}"));
        }
        let opts = unwrap_run_options(parse_args(args).expect("prefix args should parse"));
        build_wheel(&opts).expect("build_wheel should succeed");
        let entries = read_zip_entries(&out_whl);
        let record = entries
            .iter()
            .find(|e| e.name == "roots-0.0.1.dist-info/RECORD")
            .expect("RECORD entry should exist")
            .text();
        for line in record.lines() {
            assert!(
                !line.starts_with('/'),
                "RECORD line must not start with '/': {line}"
            );
        }
        entries
    };

    // Stripping `examples` (without a trailing `/`) leaves a leading `/` in `arcname_from`, which
    // `WhlFile` must strip in both zip entry headers and `RECORD`.
    let single = build_with_prefixes("single", &["examples"]);
    let single_names: Vec<&str> = single.iter().map(|e| e.name.as_str()).collect();
    assert_eq!(
        single_names,
        vec![
            "wheel/lib/mod.py",
            "wheel/main.py",
            "roots-0.0.1.dist-info/WHEEL",
            "roots-0.0.1.dist-info/METADATA",
            "roots-0.0.1.dist-info/RECORD",
        ]
    );

    // More specific prefix first strips `examples/wheel/lib` on `mod.py` and `examples/wheel` on
    // `main.py`.
    let specific_first =
        build_with_prefixes("specific_first", &["examples/wheel/lib", "examples/wheel"]);
    let specific_names: Vec<&str> = specific_first.iter().map(|e| e.name.as_str()).collect();
    assert_eq!(
        specific_names,
        vec![
            "mod.py",
            "main.py",
            "roots-0.0.1.dist-info/WHEEL",
            "roots-0.0.1.dist-info/METADATA",
            "roots-0.0.1.dist-info/RECORD",
        ]
    );

    // Broader prefix first wins for both entries, leaving `lib/mod.py` and `main.py`.
    let broad_first = build_with_prefixes("broad_first", &["examples/wheel", "examples/wheel/lib"]);
    let broad_names: Vec<&str> = broad_first.iter().map(|e| e.name.as_str()).collect();
    assert_eq!(
        broad_names,
        vec![
            "lib/mod.py",
            "main.py",
            "roots-0.0.1.dist-info/WHEEL",
            "roots-0.0.1.dist-info/METADATA",
            "roots-0.0.1.dist-info/RECORD",
        ]
    );
}

#[test]
fn test_help_and_errors() {
    assert_eq!(
        parse_args(["--help"]).expect("--help should parse"),
        Cli::Help
    );
    assert_eq!(parse_args(["-h"]).expect("-h should parse"), Cli::Help);
    assert_eq!(run_cli(["--help"]), ExitCode::SUCCESS);

    // Missing required flags (--name, --version, --metadata_file) fail in parse_args before any
    // filesystem writes.
    assert!(parse_args::<_, &str>([]).is_err());
    assert!(parse_args(["--name=pkg", "--version=1.0.0"]).is_err());
    assert!(parse_args(["--name=pkg", "--metadata_file=m.txt"]).is_err());
    assert!(parse_args(["--version=1.0.0", "--metadata_file=m.txt"]).is_err());

    // Bare "@" flagfile fails cleanly via argfile.
    assert!(parse_args(["@"]).is_err());

    // Unknown flags (including removed --description_content_type) and unexpected positional
    // arguments (including empty string) are rejected.
    assert!(
        parse_args([
            "--name=pkg",
            "--version=1.0.0",
            "--metadata_file=m.txt",
            "--compress",
        ])
        .is_err()
    );
    assert!(
        parse_args([
            "--name=pkg",
            "--version=1.0.0",
            "--metadata_file=m.txt",
            "--description_content_type=text/markdown",
        ])
        .is_err()
    );
    assert!(
        parse_args([
            "--name=pkg",
            "--version=1.0.0",
            "--metadata_file=m.txt",
            "--extra_requires_file=r.txt;dev",
        ])
        .is_err()
    );
    assert!(parse_args(["--name=pkg", "--version=1.0.0", "--metadata_file=m.txt", "",]).is_err());

    // Malformed inline Requires-Dist with empty package before `;` fails instead of passing
    // through silently.
    assert!(expand_metadata_requires("Requires-Dist: ; extra == 'dev'\n").is_err());

    // Malformed `target;real_path` flag value.
    assert!(
        parse_args([
            "--name=pkg",
            "--version=1.0.0",
            "--metadata_file=m.txt",
            "--input_file=missing_semicolon",
        ])
        .is_err()
    );

    // Malformed `input_file_list` line names the list path and line.
    let tmp = TempDir::new("errors");
    let bad_list = tmp.path().join("bad_inputs.txt");
    fs::write(&bad_list, "no_semicolon_here\n").expect("bad_inputs.txt should be writable");
    let metadata = tmp.path().join("metadata.txt");
    fs::write(&metadata, "Metadata-Version: 2.1\nName: pkg\n")
        .expect("metadata.txt should be writable");
    let out_whl = tmp.path().join("err.whl");

    let opts = unwrap_run_options(
        parse_args([
            "--name=pkg",
            "--version=1.0.0",
            &format!("--metadata_file={}", metadata.display()),
            &format!("--input_file_list={}", bad_list.display()),
            &format!("--out={}", out_whl.display()),
        ])
        .expect("args should parse"),
    );
    let err = format!("{:#}", build_wheel(&opts).unwrap_err());
    assert!(
        err.contains("no_semicolon_here") && err.contains("bad_inputs.txt"),
        "unexpected error: {err}"
    );
    assert!(!out_whl.exists());

    assert_eq!(run_cli::<_, &str>([]), ExitCode::FAILURE);
}

#[derive(Debug, Clone)]
struct ParsedZipEntry {
    /// Archive entry path relative to the zip root.
    name: String,
    system: System,
    compression: CompressionMethod,
    last_modified: Option<DateTime>,
    unix_mode: Option<u32>,
    file_size: u64,
    data: Vec<u8>,
}

impl ParsedZipEntry {
    fn text(&self) -> String {
        String::from_utf8(self.data.clone()).expect("entry bytes should be valid UTF-8")
    }
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
            "wheelmaker_test_{}_{}_{}",
            prefix,
            std::process::id(),
            id
        ));
        let _ = fs::remove_dir_all(&path);
        fs::create_dir_all(&path).expect("temp dir should be creatable");
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

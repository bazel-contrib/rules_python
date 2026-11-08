use std::collections::HashMap;
use std::env;
use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::atomic::{AtomicUsize, Ordering};

use sha2::{Digest, Sha256};
use zip_main_maker_lib::{
    Cli, Options, compute_inputs_hash, expand_template, generate_zip_main, parse_args, run_cli,
};

static TEST_COUNTER: AtomicUsize = AtomicUsize::new(0);

fn unwrap_run_options(cli: Cli) -> Options {
    match cli {
        Cli::Run(opts) => opts,
        Cli::Help => panic!("expected Cli::Run, got Cli::Help"),
    }
}

#[cfg(unix)]
fn create_symlink(target: &Path, link: &Path) {
    std::os::unix::fs::symlink(target, link).expect("symlink should be creatable");
}

#[test]
fn test_creates_zip_main() {
    let tmp = TempDir::new("creates_zip_main");
    let template_path = tmp.path().join("template.py");
    fs::write(&template_path, "hash=%APP_HASH%\nfoo=%FOO%\n").expect("template should be writable");

    let output_path = tmp.path().join("output.py");

    let file1_path = tmp.path().join("file1.txt");
    fs::write(&file1_path, b"content1").expect("file1 should be writable");

    let file2_path = tmp.path().join("file2.txt");
    fs::write(&file2_path, b"content2").expect("file2 should be writable");

    let manifest_path = tmp.path().join("manifest.txt");

    #[cfg(unix)]
    let symlink_path = {
        let sp = tmp.path().join("symlink.txt");
        create_symlink(&file1_path, &sp);
        sp
    };

    let manifest = [
        format!("rf-file|0|file1.txt|{}", file1_path.display()),
        format!("rf-file|0|file2.txt|{}", file2_path.display()),
        "rf-empty|empty_file.txt".to_string(),
    ]
    .join("\n");
    // Rebinding (rather than `Vec::push` under `#[cfg(unix)]`) keeps clippy's
    // `useless_vec`/`unused_mut` lints quiet on Windows.
    #[cfg(unix)]
    let manifest = format!(
        "{manifest}\nrf-symlink|1|symlink.txt|{}",
        symlink_path.display()
    );

    fs::write(&manifest_path, format!("{manifest}\n")).expect("manifest should be writable");

    let args: Vec<OsString> = vec![
        "--template".into(),
        template_path.as_os_str().to_owned(),
        "--output".into(),
        output_path.as_os_str().to_owned(),
        "--substitution".into(),
        "%FOO%=bar".into(),
        "--hash_files_manifest".into(),
        manifest_path.as_os_str().to_owned(),
    ];

    let options = unwrap_run_options(parse_args(&args).expect("args should parse"));
    generate_zip_main(&options).expect("generate_zip_main should succeed");

    // Entries sort lexicographically as: rf-empty, rf-file (file1), rf-file (file2), rf-symlink.
    let mut hasher = Sha256::new();
    hasher.update(b"empty_file.txt");
    hasher.update(format!("0|file1.txt|{}", file1_path.display()).as_bytes());
    hasher.update(b"content1");
    hasher.update(format!("0|file2.txt|{}", file2_path.display()).as_bytes());
    hasher.update(b"content2");
    #[cfg(unix)]
    {
        hasher.update(format!("1|symlink.txt|{}", symlink_path.display()).as_bytes());
        hasher.update(file1_path.to_string_lossy().as_bytes());
    }
    let expected_hash = format!("{:x}", hasher.finalize());

    let content = fs::read_to_string(&output_path).expect("output should be readable");
    assert_eq!(content, format!("hash={expected_hash}\nfoo=bar\n"));
}

#[test]
fn test_unsorted_manifest_determinism() {
    let tmp = TempDir::new("unsorted_manifest");
    let f1 = tmp.path().join("a.txt");
    let f2 = tmp.path().join("b.txt");
    fs::write(&f1, b"alpha").expect("f1 should be writable");
    fs::write(&f2, b"beta").expect("f2 should be writable");

    let l1 = format!("rf-file|0|a.txt|{}", f1.display());
    let l2 = format!("rf-file|0|b.txt|{}", f2.display());
    let l3 = "rf-empty|z_empty.txt".to_string();
    let l4 = "symlink|runfiles_link|/some/target".to_string();

    let manifest_a = tmp.path().join("manifest_a.txt");
    let manifest_b = tmp.path().join("manifest_b.txt");

    fs::write(&manifest_a, format!("{l4}\n{l2}\n{l3}\n{l1}\n"))
        .expect("manifest_a should be writable");
    fs::write(&manifest_b, format!("{l1}\n{l2}\n{l3}\n{l4}\n"))
        .expect("manifest_b should be writable");

    let hash_a = compute_inputs_hash(&manifest_a).expect("manifest_a hash should succeed");
    let hash_b = compute_inputs_hash(&manifest_b).expect("manifest_b hash should succeed");
    assert_eq!(hash_a, hash_b);
    assert_eq!(hash_a.len(), 64);
}

#[test]
fn test_symlink_type_hashes_rest_only() {
    let tmp = TempDir::new("symlink_type");
    // A `symlink|<runfiles_path>|<link_to_path>` entry does not open `<link_to_path>` on disk;
    // it only hashes `rest` (`<runfiles_path>|<link_to_path>`).
    let manifest = tmp.path().join("manifest.txt");
    fs::write(
        &manifest,
        "symlink|pkg/link.py|/nonexistent/target/on/disk.py\nrf-empty|pkg/__init__.py\n",
    )
    .expect("manifest should be writable");

    let actual_hash = compute_inputs_hash(&manifest).expect("manifest hash should succeed");

    let mut hasher = Sha256::new();
    // "rf-empty|pkg/__init__.py" sorts before "symlink|pkg/link.py|/nonexistent/target/on/disk.py"
    hasher.update(b"pkg/__init__.py");
    hasher.update(b"pkg/link.py|/nonexistent/target/on/disk.py");
    let expected_hash = format!("{:x}", hasher.finalize());

    assert_eq!(actual_hash, expected_hash);
}

#[test]
fn test_empty_manifest_and_empty_substitution_value() {
    let tmp = TempDir::new("empty_manifest");
    let manifest = tmp.path().join("empty.manifest");
    fs::write(&manifest, "").expect("empty manifest should be writable");

    let tpl = tmp.path().join("tpl.py");
    fs::write(&tpl, "OPT='%OPT%'\nHASH='%APP_HASH%'\n").expect("template should be writable");

    let out = tmp.path().join("out.py");
    let code = run_cli([
        "--template",
        tpl.to_str().expect("tpl path should be UTF-8"),
        "--hash_files_manifest",
        manifest.to_str().expect("manifest path should be UTF-8"),
        "--substitution",
        "%OPT%=",
        "--output",
        out.to_str().expect("out path should be UTF-8"),
    ]);
    assert_eq!(code, ExitCode::SUCCESS);

    let empty_sha256 = format!("{:x}", Sha256::new().finalize());
    let rendered = fs::read_to_string(&out).expect("output should be readable");
    assert_eq!(rendered, format!("OPT=''\nHASH='{empty_sha256}'\n"));
}

#[cfg(unix)]
#[test]
fn test_is_symlink_minus_one_valid_vs_broken() {
    let tmp = TempDir::new("symlink_minus_one");
    let real_file = tmp.path().join("real.txt");
    fs::write(&real_file, b"real_file_bytes").expect("real_file should be writable");

    // Symlink pointing to an existing file: `path.exists()` is true -> `is_symlink` is false ->
    // hashes file content.
    let valid_symlink = tmp.path().join("valid_sym.txt");
    create_symlink(&real_file, &valid_symlink);

    // Dangling symlink pointing to a non-existent file: `path.exists()` is false -> `is_symlink`
    // is true -> hashes readlink target.
    let missing_target = tmp.path().join("does_not_exist.txt");
    let broken_symlink = tmp.path().join("broken_sym.txt");
    create_symlink(&missing_target, &broken_symlink);

    let manifest_valid = tmp.path().join("manifest_valid.txt");
    let line_valid = format!("rf-file|-1|valid_sym.txt|{}", valid_symlink.display());
    fs::write(&manifest_valid, format!("{line_valid}\n"))
        .expect("manifest_valid should be writable");

    let hash_valid = compute_inputs_hash(&manifest_valid).expect("valid hash should succeed");
    let mut h_valid = Sha256::new();
    h_valid.update(line_valid.split_once('|').unwrap().1.as_bytes());
    h_valid.update(b"real_file_bytes");
    assert_eq!(hash_valid, format!("{:x}", h_valid.finalize()));

    let manifest_broken = tmp.path().join("manifest_broken.txt");
    let line_broken = format!("rf-file|-1|broken_sym.txt|{}", broken_symlink.display());
    fs::write(&manifest_broken, format!("{line_broken}\n"))
        .expect("manifest_broken should be writable");

    let hash_broken = compute_inputs_hash(&manifest_broken).expect("broken hash should succeed");
    let mut h_broken = Sha256::new();
    h_broken.update(line_broken.split_once('|').unwrap().1.as_bytes());
    h_broken.update(missing_target.to_string_lossy().as_bytes());
    assert_eq!(hash_broken, format!("{:x}", h_broken.finalize()));
}

#[test]
fn test_flagfile_and_equals_flags_and_multiple_substitutions() {
    let tmp = TempDir::new("flagfile_and_subst");
    let template_path = tmp.path().join("template.py");
    fs::write(
        &template_path,
        "hash=%APP_HASH%\ndir=%EXTRACT_DIR%\nbin=%python_binary%\nws=%workspace_name%\n",
    )
    .expect("template should be writable");

    let output_path = tmp.path().join("nested").join("output.py");
    let manifest_path = tmp.path().join("manifest.txt");
    fs::write(&manifest_path, "rf-empty|__init__.py\n").expect("manifest should be writable");

    let flagfile_path = tmp.path().join("args.params");
    fs::write(
        &flagfile_path,
        format!(
            "--template={}\n--output\n{}\n--substitution=%EXTRACT_DIR%=_main/pkg/app\n--substitution=%python_binary%=old_val\n",
            template_path.display(),
            output_path.display(),
        ),
    )
    .expect("flagfile should be writable");

    let args = vec![
        format!("@{}", flagfile_path.display()),
        "--substitution".to_string(),
        "%python_binary%=venv/bin/python3".to_string(),
        "--substitution=%workspace_name%=my_ws=with_eq".to_string(),
        format!("--hash_files_manifest={}", manifest_path.display()),
    ];

    let options = unwrap_run_options(parse_args(&args).expect("flagfile args should parse"));
    assert_eq!(options.template, template_path);
    assert_eq!(options.output, output_path);
    assert_eq!(options.hash_files_manifest, manifest_path);
    assert_eq!(run_cli(&args), ExitCode::SUCCESS);

    let expected_hash = compute_inputs_hash(&manifest_path).expect("manifest hash should succeed");
    let content = fs::read_to_string(&output_path).expect("output should be readable");
    assert_eq!(
        content,
        format!(
            "hash={expected_hash}\ndir=_main/pkg/app\nbin=venv/bin/python3\nws=my_ws=with_eq\n"
        )
    );
}

#[test]
fn test_substitution_overwrite_and_app_hash_override() {
    let options = unwrap_run_options(
        parse_args([
            "--template=tpl.txt",
            "--output=out.txt",
            "--hash_files_manifest=manifest.txt",
            "--substitution=%FOO%=first",
            "--substitution=%BAR%=bar_val",
            "--substitution=%FOO%=second",
        ])
        .expect("args should parse"),
    );
    assert_eq!(
        options.substitutions,
        HashMap::from([
            ("%BAR%".to_string(), "bar_val".to_string()),
            ("%FOO%".to_string(), "second".to_string()),
        ])
    );

    let tmp = TempDir::new("subst_overwrite");
    let tpl = tmp.path().join("tpl.txt");
    let out = tmp.path().join("out.txt");
    fs::write(&tpl, "%APP_HASH% %FOO% %BAR%").expect("tpl should be writable");
    expand_template(
        &tpl,
        &out,
        &HashMap::from([
            ("%APP_HASH%", "deadbeef"),
            ("%FOO%", "second"),
            ("%BAR%", "bar_val"),
        ]),
    )
    .expect("expand_template should succeed");
    assert_eq!(
        fs::read_to_string(&out).expect("out should be readable"),
        "deadbeef second bar_val"
    );
}

#[cfg(unix)]
#[test]
fn test_is_symlink_zero_vs_one_on_symlink() {
    let tmp = TempDir::new("symlink_zero_vs_one");
    let target_file = tmp.path().join("target.txt");
    fs::write(&target_file, b"target_file_payload").expect("target_file should be writable");

    let sym = tmp.path().join("sym.txt");
    create_symlink(&target_file, &sym);

    // When is_symlink == "0", it opens `sym` (following the symlink) and hashes the target file's
    // bytes.
    let manifest_0 = tmp.path().join("manifest_0.txt");
    let line_0 = format!("rf-file|0|sym.txt|{}", sym.display());
    fs::write(&manifest_0, format!("{line_0}\n")).expect("manifest_0 should be writable");

    let hash_0 = compute_inputs_hash(&manifest_0).expect("manifest_0 hash should succeed");
    let mut h0 = Sha256::new();
    h0.update(line_0.split_once('|').unwrap().1.as_bytes());
    h0.update(b"target_file_payload");
    assert_eq!(hash_0, format!("{:x}", h0.finalize()));

    // When is_symlink == "1", it reads the symlink target path via readlink and hashes the path
    // bytes.
    let manifest_1 = tmp.path().join("manifest_1.txt");
    let line_1 = format!("rf-symlink|1|sym.txt|{}", sym.display());
    fs::write(&manifest_1, format!("{line_1}\n")).expect("manifest_1 should be writable");

    let hash_1 = compute_inputs_hash(&manifest_1).expect("manifest_1 hash should succeed");
    let mut h1 = Sha256::new();
    h1.update(line_1.split_once('|').unwrap().1.as_bytes());
    h1.update(target_file.to_string_lossy().as_bytes());
    assert_eq!(hash_1, format!("{:x}", h1.finalize()));
    assert_ne!(hash_0, hash_1);
}

#[test]
fn test_large_file_streaming_and_crlf_manifest() {
    let tmp = TempDir::new("large_file_crlf");
    let large_file = tmp.path().join("large.bin");
    let payload: Vec<u8> = (0..(600 * 1024)).map(|i| (i % 251) as u8).collect();
    fs::write(&large_file, &payload).expect("large_file should be writable");

    let line1 = format!("rf-file|0|large.bin|{}", large_file.display());
    let line2 = "rf-empty|empty.py";

    let manifest_crlf = tmp.path().join("manifest_crlf.txt");
    fs::write(&manifest_crlf, format!("{line1}\r\n{line2}\r\n"))
        .expect("manifest_crlf should be writable");

    let manifest_lf = tmp.path().join("manifest_lf.txt");
    fs::write(&manifest_lf, format!("{line1}\n{line2}\n")).expect("manifest_lf should be writable");

    let hash_crlf = compute_inputs_hash(&manifest_crlf).expect("CRLF manifest should hash");
    let hash_lf = compute_inputs_hash(&manifest_lf).expect("LF manifest should hash");
    assert_eq!(hash_crlf, hash_lf);

    let mut expected = Sha256::new();
    // "rf-empty|empty.py" sorts before "rf-file|0|large.bin|..."
    expected.update(b"empty.py");
    expected.update(line1.split_once('|').unwrap().1.as_bytes());
    expected.update(&payload);
    assert_eq!(hash_lf, format!("{:x}", expected.finalize()));
}

#[test]
fn test_help_and_errors() {
    assert_eq!(
        parse_args(["--help"]).expect("--help should parse"),
        Cli::Help
    );
    assert_eq!(parse_args(["-h"]).expect("-h should parse"), Cli::Help);
    assert_eq!(run_cli(["--help"]), ExitCode::SUCCESS);

    // Missing required flags.
    assert!(parse_args::<_, &str>([]).is_err());
    assert!(parse_args(["--template=a", "--output=b"]).is_err());

    // Bare "@" flagfile fails cleanly via argfile.
    assert!(parse_args(["@"]).is_err());

    // Invalid substitution without '='.
    assert!(
        parse_args([
            "--template=a",
            "--output=b",
            "--hash_files_manifest=c",
            "--substitution=NO_EQUALS",
        ])
        .is_err()
    );

    // Unknown flag.
    assert!(
        parse_args([
            "--template=a",
            "--output=b",
            "--hash_files_manifest=c",
            "--unknown=1",
        ])
        .is_err()
    );

    // Unexpected positional arg.
    assert!(
        parse_args([
            "--template=a",
            "--output=b",
            "--hash_files_manifest=c",
            "extra",
        ])
        .is_err()
    );

    // Malformed manifest lines and missing input files name the offending path/line.
    let tmp = TempDir::new("errors");
    let bad_manifest = tmp.path().join("bad_manifest.txt");
    fs::write(&bad_manifest, "no_pipe_delimiter\n").expect("bad_manifest should be writable");
    let err = format!("{:#}", compute_inputs_hash(&bad_manifest).unwrap_err());
    assert!(err.contains("no_pipe_delimiter"), "unexpected err: {err}");

    let bad_mode = tmp.path().join("bad_mode.txt");
    fs::write(&bad_mode, "rf-file|9|a.py|/nonexistent/a.py\n")
        .expect("bad_mode should be writable");
    let err = format!("{:#}", compute_inputs_hash(&bad_mode).unwrap_err());
    assert!(
        err.contains("invalid is_symlink value"),
        "unexpected err: {err}"
    );

    let unknown_type = tmp.path().join("unknown_type.txt");
    fs::write(&unknown_type, "unknown|0|a.py|/nonexistent/a.py\n")
        .expect("unknown_type should be writable");
    let err = format!("{:#}", compute_inputs_hash(&unknown_type).unwrap_err());
    assert!(
        err.contains("unknown entry type or invalid format"),
        "unexpected err: {err}"
    );

    let truncated_line = tmp.path().join("truncated_line.txt");
    fs::write(&truncated_line, "rf-file|0|a.py\n").expect("truncated_line should be writable");
    let err = format!("{:#}", compute_inputs_hash(&truncated_line).unwrap_err());
    assert!(
        err.contains("unknown entry type or invalid format"),
        "unexpected err: {err}"
    );

    assert_eq!(run_cli::<_, &str>([]), ExitCode::FAILURE);
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
            "zip_main_maker_test_{}_{}_{}",
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

use std::path::Path;

use zip_manifest::{
    ManifestLine, ManifestParseError, RawManifestEntry, SymlinkMode, parse_manifest_line,
    parse_symlink_mode,
};

#[test]
fn test_parse_all_valid_entry_kinds() {
    let regular = parse_manifest_line("regular|0|__main__.py|bazel-out/main.py")
        .expect("regular entry should parse");
    assert_eq!(
        regular,
        ManifestLine {
            rest: "0|__main__.py|bazel-out/main.py",
            entry: RawManifestEntry::Regular {
                symlink_mode: SymlinkMode::Regular,
                zip_path: "__main__.py",
                content_path: Path::new("bazel-out/main.py"),
            },
        }
    );
    assert_eq!(
        regular.entry.content_source(),
        Some((SymlinkMode::Regular, Path::new("bazel-out/main.py")))
    );

    let rf_empty =
        parse_manifest_line("rf-empty|pkg/__init__.py").expect("rf-empty entry should parse");
    assert_eq!(
        rf_empty,
        ManifestLine {
            rest: "pkg/__init__.py",
            entry: RawManifestEntry::RfEmpty {
                runfile_path: "pkg/__init__.py",
            },
        }
    );
    assert_eq!(rf_empty.entry.content_source(), None);

    let rf_file = parse_manifest_line("rf-file|-1|pkg/app.py|src/pkg/app.py")
        .expect("rf-file entry should parse");
    assert_eq!(
        rf_file.entry,
        RawManifestEntry::RfFile {
            symlink_mode: SymlinkMode::Infer,
            runfile_path: "pkg/app.py",
            content_path: Path::new("src/pkg/app.py"),
        }
    );
    assert_eq!(
        rf_file.entry.content_source(),
        Some((SymlinkMode::Infer, Path::new("src/pkg/app.py")))
    );

    let rf_symlink = parse_manifest_line("rf-symlink|1|pkg/link.py|src/pkg/link.py")
        .expect("rf-symlink entry should parse");
    assert_eq!(
        rf_symlink.entry,
        RawManifestEntry::RfSymlink {
            symlink_mode: SymlinkMode::Symlink,
            runfile_symlink_path: "pkg/link.py",
            content_path: Path::new("src/pkg/link.py"),
        }
    );

    let rf_root = parse_manifest_line("rf-root-symlink|0|_repo_mapping|bazel-out/_repo_mapping")
        .expect("rf-root-symlink entry should parse");
    assert_eq!(
        rf_root.entry,
        RawManifestEntry::RfRootSymlink {
            symlink_mode: SymlinkMode::Regular,
            runfile_root_path: "_repo_mapping",
            content_path: Path::new("bazel-out/_repo_mapping"),
        }
    );

    let symlink = parse_manifest_line("symlink|_main/venv/bin/python|_main/py/bin/python3")
        .expect("symlink entry should parse");
    assert_eq!(
        symlink,
        ManifestLine {
            rest: "_main/venv/bin/python|_main/py/bin/python3",
            entry: RawManifestEntry::Symlink {
                runfile_root_path: "_main/venv/bin/python",
                link_to_runfile_root_path: "_main/py/bin/python3",
            },
        }
    );
    assert_eq!(symlink.entry.content_source(), None);
}

#[test]
fn test_parse_errors() {
    assert_eq!(
        parse_symlink_mode("2"),
        Err(ManifestParseError::InvalidSymlinkMode {
            value: "2".to_string()
        })
    );
    assert_eq!(
        parse_manifest_line("missing_delimiter"),
        Err(ManifestParseError::InvalidFormat {
            line: "missing_delimiter".to_string()
        })
    );
    assert_eq!(
        parse_manifest_line("unknown|0|a|b"),
        Err(ManifestParseError::InvalidFormat {
            line: "unknown|0|a|b".to_string()
        })
    );
    assert_eq!(
        parse_manifest_line("rf-empty|too|many"),
        Err(ManifestParseError::InvalidFormat {
            line: "rf-empty|too|many".to_string()
        })
    );
    assert_eq!(
        parse_manifest_line("rf-file|0|missing_content_path"),
        Err(ManifestParseError::InvalidFormat {
            line: "rf-file|0|missing_content_path".to_string()
        })
    );
    assert_eq!(
        parse_manifest_line("rf-file|9|a|b"),
        Err(ManifestParseError::InvalidSymlinkMode {
            value: "9".to_string()
        })
    );
}

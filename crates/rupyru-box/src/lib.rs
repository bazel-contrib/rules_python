//! Unified `rupyru-box` ("rules python rust box") subcommand dispatcher for `@rules_python`
//! Rust build tools.

use std::ffi::OsString;
use std::path::Path;

/// Canonical subcommand names supported by `rupyru-box`.
pub const SUBCOMMANDS: &[&str] = &["exe_zip_maker"];

fn print_usage(prog_name: &str, to_stderr: bool) {
    let msg = format!(
        "Usage: {} <subcommand> [args...]\n\nAvailable subcommands:\n  {}",
        prog_name,
        SUBCOMMANDS.join("\n  ")
    );
    if to_stderr {
        eprintln!("{}", msg);
    } else {
        println!("{}", msg);
    }
}

/// Dispatches CLI arguments (including `argv[0]`) to the requested subcommand and returns the
/// process exit code.
pub fn run_cli<I, T>(args: I) -> i32
where
    I: IntoIterator<Item = T>,
    T: Into<OsString>,
{
    let mut iter = args.into_iter().map(Into::into);
    let prog_name = iter
        .next()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| "rupyru-box".to_string());

    let Some(sub_os) = iter.next() else {
        print_usage(&prog_name, true);
        return 1;
    };
    let sub_raw = sub_os.to_string_lossy();
    if sub_raw == "-h" || sub_raw == "--help" || sub_raw == "help" {
        print_usage(&prog_name, false);
        return 0;
    }

    let normalized = if sub_raw.starts_with('-') {
        sub_raw.as_ref().to_owned()
    } else {
        sub_raw.replace('-', "_")
    };

    let os_args: Vec<OsString> = iter.collect();

    match normalized.as_str() {
        "exe_zip_maker" => {
            if os_args.len() != 3 {
                eprintln!(
                    "Usage: {} exe_zip_maker <preamble> <zip> <output>",
                    prog_name
                );
                return 1;
            }
            let preamble_path = Path::new(&os_args[0]);
            let zip_path = Path::new(&os_args[1]);
            let output_path = Path::new(&os_args[2]);
            if let Err(e) = exe_zip_maker_lib::create_exe_zip(preamble_path, zip_path, output_path)
            {
                eprintln!("exe_zip_maker: error: {}", e);
                return 1;
            }
            0
        }
        _ => {
            eprintln!("rupyru-box: error: unknown subcommand '{}'", sub_raw);
            print_usage(&prog_name, true);
            1
        }
    }
}

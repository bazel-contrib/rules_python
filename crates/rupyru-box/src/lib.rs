//! Unified `rupyru-box` ("rules python rust box") subcommand dispatcher for `@rules_python`
//! Rust build tools.

use std::ffi::OsString;

/// Canonical subcommand names supported by `rupyru-box`.
pub const SUBCOMMANDS: &[&str] = &[
    // keep-sorted start
    "exe_zip_maker",
    // keep-sorted end
];

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

    match sub_raw.as_ref() {
        "exe_zip_maker" => exe_zip_maker_lib::run_cli(iter),
        _ => {
            eprintln!("rupyru-box: error: unknown subcommand '{}'", sub_raw);
            print_usage(&prog_name, true);
            1
        }
    }
}

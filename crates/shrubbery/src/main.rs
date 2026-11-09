// Errors must be returned, not panicked; see the `rust-lint` config in .bazelrc.
#![deny(clippy::expect_used, clippy::unwrap_used)]

use std::env;
use std::process;

fn main() {
    process::exit(shrubbery_lib::run_cli(env::args_os()));
}
